import abilityAccessCtrl from '@ohos.abilityAccessCtrl'
import camera from '@ohos.multimedia.camera'
import image from '@ohos.multimedia.image'
import { media } from '@kit.MediaKit'
import window from '@ohos.window'
import { common } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { router } from '@kit.ArkUI'
import {
  getYoloModelInfo,
  inferYoloPixelMap,
  inferYoloYuv420,
  initializeYoloAsync,
  NativeDetection,
  NativeLiveInferenceResult,
  YoloModelInfo
} from '../native/YoloNativeBridge'
import {
  MonitoringScene,
  RestrictedZone,
  RuleAlert,
  RuleDetection,
  RuleEvaluation,
  SceneRuleEngine
} from '../rules/SceneRuleEngine'

const DOMAIN: number = 0x0000
const TAG: string = 'LiveCamera'
const TARGET_WIDTH: number = 1280
const TARGET_HEIGHT: number = 720
const CAMERA_FRAME_TIMEOUT_MS: number = 3000
const DETECTION_MIN_INTERVAL_MS: number = 100
const ANALYSIS_WIDTH: number = 640
const ANALYSIS_HEIGHT: number = 360

const COCO_LABELS: string[] = [
  'person', 'bicycle', 'car', 'motorcycle', 'airplane', 'bus', 'train', 'truck', 'boat',
  'traffic light', 'fire hydrant', 'stop sign', 'parking meter', 'bench', 'bird', 'cat',
  'dog', 'horse', 'sheep', 'cow', 'elephant', 'bear', 'zebra', 'giraffe', 'backpack',
  'umbrella', 'handbag', 'tie', 'suitcase', 'frisbee', 'skis', 'snowboard', 'sports ball',
  'kite', 'baseball bat', 'baseball glove', 'skateboard', 'surfboard', 'tennis racket',
  'bottle', 'wine glass', 'cup', 'fork', 'knife', 'spoon', 'bowl', 'banana', 'apple',
  'sandwich', 'orange', 'broccoli', 'carrot', 'hot dog', 'pizza', 'donut', 'cake',
  'chair', 'couch', 'potted plant', 'bed', 'dining table', 'toilet', 'tv', 'laptop',
  'mouse', 'remote', 'keyboard', 'cell phone', 'microwave', 'oven', 'toaster', 'sink',
  'refrigerator', 'book', 'clock', 'vase', 'scissors', 'teddy bear', 'hair drier', 'toothbrush'
]

@Entry
@Component
struct LiveCamera {
  @State statusText: string = '正在准备摄像头…'
  @State isCameraReady: boolean = false
  @State detectionCount: number = 0
  @State inferenceText: string = '-- ms'
  @State sceneMode: MonitoringScene = MonitoringScene.WORK
  @State restrictedZone: RestrictedZone = RestrictedZone.RIGHT
  @State rulePrimaryStatus: string = '人员：等待检测'
  @State ruleSecondaryStatus: string = '手机：等待检测'
  @State ruleDetailStatus: string = '设备：准备学习基线'
  @State latestAlertTitle: string = ''
  @State latestAlertMessage: string = ''
  @State latestAlertSeverity: number = 0
  @State voiceEnabled: boolean = true
  @State voiceStatus: string = '语音就绪'
  @State activeRuleKeys: string[] = []

  private previewController: XComponentController = new XComponentController()
  private overlaySettings: RenderingContextSettings = new RenderingContextSettings(true)
  private overlayContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.overlaySettings)
  private previewSurfaceId: string = ''
  private previewWidth: number = TARGET_WIDTH
  private previewHeight: number = TARGET_HEIGHT
  // The 310B USB-camera HCS is OTHER/USB_PLUGIN with mirrorSupported=OFF;
  // keep overlay and rule coordinates in the same (unmirrored) space.
  private previewMirrored: boolean = false
  private surfaceCaptureEnabled: boolean = false
  // Prefer the low-latency YUV analysis stream.  If this camera does not
  // expose a usable YUV420 profile, startCamera() falls back to JPEG capture.
  private enableContinuousYuv: boolean = true
  private cameraManager: camera.CameraManager | undefined = undefined
  private cameraInput: camera.CameraInput | undefined = undefined
  private previewOutput: camera.PreviewOutput | undefined = undefined
  private analysisOutput: camera.VideoOutput | undefined = undefined
  private analysisReceiver: image.ImageReceiver | undefined = undefined
  private photoOutput: camera.PhotoOutput | undefined = undefined
  private captureSession: camera.VideoSession | undefined = undefined
  private detectionTimerId: number = -1
  private detectionLoopActive: boolean = false
  private analysisReadBusy: boolean = false
  private lastDetectionFinishedAt: number = 0
  private inferenceBusy: boolean = false
  private frameCaptureBusy: boolean = false
  private frameCaptureStartedAt: number = 0
  private pageActive: boolean = false
  private cameraStartGeneration: number = 0
  private modelReady: boolean = false
  private detections: NativeDetection[] = []
  private detectionTickCount: number = 0
  private completedDetectionCount: number = 0
  private ruleEngine: SceneRuleEngine = new SceneRuleEngine()
  private ruleHighlightLabels: string[] = []
  private latestAlertTimerId: number = -1
  private audioPlayer: media.AVPlayer | null = null
  private audioQueue: string[] = []
  private audioBusy: boolean = false
  private currentAudioFile: string = ''
  private pipelineReleaseInProgress: Promise<void> | undefined = undefined

  aboutToAppear(): void {
    this.cameraStartGeneration += 1
    this.pageActive = true
    this.ruleEngine.setScene(this.sceneMode, Date.now())
    this.ruleEngine.setRestrictedZone(this.restrictedZone)
    this.setKeepScreenOn(true)
    this.prepareModel()
  }

  aboutToDisappear(): void {
    this.cameraStartGeneration += 1
    this.pageActive = false
    this.setKeepScreenOn(false)
    this.stopDetectionLoop()
    this.releasePipeline()
    if (this.latestAlertTimerId !== -1) {
      clearTimeout(this.latestAlertTimerId)
      this.latestAlertTimerId = -1
    }
    this.stopAlertAudio()
  }

  private async setKeepScreenOn(enabled: boolean): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext
      const appWindow = await window.getLastWindow(context)
      await appWindow.setWindowKeepScreenOn(enabled)
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Keep-screen-on update failed: %{public}s', JSON.stringify(error))
    }
  }

  private sceneName(scene: MonitoringScene = this.sceneMode): string {
    if (scene === MonitoringScene.SECURITY) return '安检'
    if (scene === MonitoringScene.PUBLIC) return '公共'
    return '工作'
  }

  private zoneName(): string {
    if (this.restrictedZone === RestrictedZone.LEFT) return '左侧'
    if (this.restrictedZone === RestrictedZone.RIGHT) return '右侧'
    return '关闭'
  }

  private selectScene(scene: MonitoringScene): void {
    if (this.sceneMode === scene) return
    this.sceneMode = scene
    this.ruleEngine.setScene(scene, Date.now())
    this.ruleEngine.setRestrictedZone(this.restrictedZone)
    this.activeRuleKeys = []
    this.ruleHighlightLabels = []
    this.latestAlertTitle = ''
    this.latestAlertMessage = ''
    if (scene === MonitoringScene.WORK) {
      this.rulePrimaryStatus = '人员：等待检测'
      this.ruleSecondaryStatus = '手机：等待检测'
      this.ruleDetailStatus = '设备：准备学习基线'
    } else if (scene === MonitoringScene.SECURITY) {
      this.rulePrimaryStatus = '危险物：等待检测'
      this.ruleSecondaryStatus = '食品饮品：等待检测'
      this.ruleDetailStatus = '包裹行李：等待检测'
    } else {
      this.rulePrimaryStatus = '遗留物：开始计时观察'
      this.ruleSecondaryStatus = '人群：等待检测'
      this.ruleDetailStatus = '环境：等待检测'
    }
    this.drawDetections()
  }

  private cycleRestrictedZone(): void {
    if (this.restrictedZone === RestrictedZone.RIGHT) {
      this.restrictedZone = RestrictedZone.LEFT
    } else if (this.restrictedZone === RestrictedZone.LEFT) {
      this.restrictedZone = RestrictedZone.OFF
    } else {
      this.restrictedZone = RestrictedZone.RIGHT
    }
    this.ruleEngine.setRestrictedZone(this.restrictedZone)
    this.drawDetections()
  }

  private toggleVoice(): void {
    this.voiceEnabled = !this.voiceEnabled
    if (this.voiceEnabled) {
      this.voiceStatus = '语音就绪'
    } else {
      this.voiceStatus = '语音已关闭'
      this.stopAlertAudio()
    }
  }

  private testVoicePlayback(): void {
    if (!this.voiceEnabled) {
      this.voiceEnabled = true
      this.voiceStatus = '语音就绪'
    }
    this.enqueueAlertAudio('work_on_duty.mp3')
  }

  private applyInferenceResult(result: NativeLiveInferenceResult, endToEndMs: number): void {
    this.detections = result.detections
    this.detectionCount = result.detections.length
    this.inferenceText = `${result.inferenceMs.toFixed(1)} ms NPU / ` +
      `${result.totalMs.toFixed(1)} ms native / ${endToEndMs.toFixed(0)} ms end-to-end`
    this.evaluateSceneRules()
    this.drawDetections()
  }

  private mapDetectionX(detection: NativeDetection): number {
    return this.previewMirrored ? 1 - detection.x - detection.width : detection.x
  }

  private evaluateSceneRules(): void {
    const ruleDetections: RuleDetection[] = []
    for (let index = 0; index < this.detections.length; index++) {
      const detection = this.detections[index]
      const label = COCO_LABELS[detection.classId] || `class ${detection.classId}`
      const mirroredX = Math.max(0, Math.min(1, this.mapDetectionX(detection)))
      ruleDetections.push(new RuleDetection(detection.classId, label, detection.score,
        mirroredX, detection.y, detection.width, detection.height))
    }
    const evaluation: RuleEvaluation = this.ruleEngine.evaluate(ruleDetections, Date.now())
    this.rulePrimaryStatus = evaluation.primaryStatus
    this.ruleSecondaryStatus = evaluation.secondaryStatus
    this.ruleDetailStatus = evaluation.detailStatus
    this.activeRuleKeys = evaluation.activeKeys
    this.ruleHighlightLabels = evaluation.highlightLabels

    let mostImportant: RuleAlert | undefined = undefined
    for (let index = 0; index < evaluation.alerts.length; index++) {
      const alert = evaluation.alerts[index]
      if (mostImportant === undefined || alert.severity > mostImportant.severity) mostImportant = alert
      this.enqueueAlertAudio(alert.audioFile)
      hilog.warn(DOMAIN, TAG, 'Rule alert: %{public}s %{public}s', alert.key, alert.message)
    }
    if (mostImportant !== undefined) this.showRuleAlert(mostImportant)
  }

  private showRuleAlert(alert: RuleAlert): void {
    this.latestAlertTitle = alert.title
    this.latestAlertMessage = alert.message
    this.latestAlertSeverity = alert.severity
    if (this.latestAlertTimerId !== -1) clearTimeout(this.latestAlertTimerId)
    this.latestAlertTimerId = setTimeout(() => {
      this.latestAlertTitle = ''
      this.latestAlertMessage = ''
      this.latestAlertTimerId = -1
    }, 7000)
  }

  private enqueueAlertAudio(audioFile: string): void {
    if (!this.voiceEnabled || audioFile.length === 0) return
    if (audioFile === this.currentAudioFile || this.audioQueue.indexOf(audioFile) >= 0) return
    this.audioQueue.push(audioFile)
    this.playNextAlertAudio()
  }

  private async playNextAlertAudio(): Promise<void> {
    if (this.audioBusy || !this.voiceEnabled || !this.pageActive || this.audioQueue.length === 0) return
    const audioFile = this.audioQueue.shift()
    if (audioFile === undefined) return
    this.audioBusy = true
    this.currentAudioFile = audioFile
    this.voiceStatus = '正在准备语音'
    try {
      const player: media.AVPlayer = await media.createAVPlayer()
      this.audioPlayer = player
      player.on('stateChange', (state: string) => {
        hilog.info(DOMAIN, TAG, 'Alert audio %{public}s state=%{public}s', audioFile, state)
        if (state === 'initialized') {
          player.prepare()
        } else if (state === 'prepared') {
          player.play()
        } else if (state === 'playing') {
          this.voiceStatus = '正在播报'
        } else if (state === 'completed') {
          this.finishAlertAudio(player)
        }
      })
      player.on('error', (error: Error) => {
        hilog.error(DOMAIN, TAG, 'Alert audio failed: %{public}s', error.message)
        this.finishAlertAudio(player)
      })
      const context = getContext(this) as common.UIAbilityContext
      const resource = await context.resourceManager.getRawFileDescriptor(audioFile)
      const source: media.AVFileDescriptor = {
        fd: resource.fd,
        offset: resource.offset,
        length: resource.length
      }
      player.fdSrc = source
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Alert audio setup failed: %{public}s', JSON.stringify(error))
      if (this.audioPlayer !== null) {
        this.finishAlertAudio(this.audioPlayer)
      } else {
        this.audioBusy = false
        this.currentAudioFile = ''
        this.voiceStatus = '语音播放失败'
      }
    }
  }

  private async finishAlertAudio(player: media.AVPlayer): Promise<void> {
    if (this.audioPlayer !== player) return
    this.audioPlayer = null
    this.audioBusy = false
    this.currentAudioFile = ''
    try {
      await player.release()
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Alert audio release failed: %{public}s', JSON.stringify(error))
    }
    if (this.voiceEnabled && this.audioQueue.length > 0) {
      this.voiceStatus = '等待下一条语音'
      setTimeout(() => this.playNextAlertAudio(), 150)
    } else {
      this.voiceStatus = this.voiceEnabled ? '语音就绪' : '语音已关闭'
    }
  }

  private async stopAlertAudio(): Promise<void> {
    this.audioQueue = []
    const player = this.audioPlayer
    this.audioPlayer = null
    this.audioBusy = false
    this.currentAudioFile = ''
    if (player !== null) {
      try {
        await player.release()
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'Stop alert audio failed: %{public}s', JSON.stringify(error))
      }
    }
    this.voiceStatus = this.voiceEnabled ? '语音就绪' : '语音已关闭'
  }

  private async prepareModel(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext
      const current: YoloModelInfo = getYoloModelInfo()
      const info: YoloModelInfo = current.initialized ? current : await initializeYoloAsync(context.resourceManager, 0)
      this.modelReady = true
      if (this.pageActive && this.isCameraReady) {
        this.statusText = '摄像头和模型已就绪，正在实时检测'
        this.startDetectionLoop()
      }
      hilog.info(DOMAIN, TAG, 'YOLO ready: %{public}s', JSON.stringify(info))
    } catch (error) {
      this.statusText = `模型初始化失败：${(error as Error).message}`
      hilog.error(DOMAIN, TAG, 'YOLO init failed: %{public}s', JSON.stringify(error))
    }
  }

  private async ensureCameraPermission(): Promise<boolean> {
    const context = getContext(this) as common.UIAbilityContext
    const manager = abilityAccessCtrl.createAtManager()
    const result = await manager.requestPermissionsFromUser(context, ['ohos.permission.CAMERA'])
    return result.authResults.length > 0 && result.authResults[0] === 0
  }

  private profileDistance(profile: camera.Profile): number {
    const widthDelta = profile.size.width - TARGET_WIDTH
    const heightDelta = profile.size.height - TARGET_HEIGHT
    const ratio = profile.size.width / Math.max(1, profile.size.height)
    const ratioDelta = ratio - (16 / 9)
    return Math.abs(widthDelta) + Math.abs(heightDelta) + Math.abs(ratioDelta) * 10000
  }

  private chooseProfile(profiles: camera.Profile[]): camera.Profile {
    if (profiles.length === 0) {
      throw new Error('摄像头没有可用的图像输出规格')
    }
    let best: camera.Profile = profiles[0]
    let bestScore: number = this.profileDistance(best)
    for (let index = 1; index < profiles.length; index++) {
      const score = this.profileDistance(profiles[index])
      if (score < bestScore) {
        best = profiles[index]
        bestScore = score
      }
    }
    return best
  }

  private chooseAnalysisProfile(profiles: camera.VideoProfile[]): camera.VideoProfile | undefined {
    let best: camera.VideoProfile | undefined = undefined
    let bestScore: number = Number.MAX_VALUE
    for (let index = 0; index < profiles.length; index++) {
      const profile = profiles[index]
      if (profile.format !== camera.CameraFormat.CAMERA_FORMAT_YUV_420_SP) continue
      const ratio = profile.size.width / Math.max(1, profile.size.height)
      const score = Math.abs(profile.size.width - ANALYSIS_WIDTH) +
        Math.abs(profile.size.height - ANALYSIS_HEIGHT) + Math.abs(ratio - (16 / 9)) * 1000
      if (score < bestScore) {
        best = profile
        bestScore = score
      }
    }
    return best
  }

  private async startCamera(surfaceId: string): Promise<void> {
    if (!this.pageActive || this.isCameraReady || surfaceId.length === 0) return
    const startGeneration = this.cameraStartGeneration
    // Serialize a quick leave/re-enter with the previous HDI teardown.
    const pendingRelease = this.pipelineReleaseInProgress
    if (pendingRelease) await pendingRelease
    if (!this.pageActive || startGeneration !== this.cameraStartGeneration) return
    this.statusText = '正在申请摄像头权限…'
    try {
      if (!await this.ensureCameraPermission()) {
        this.statusText = '未获得摄像头权限'
        return
      }
      if (!this.pageActive || startGeneration !== this.cameraStartGeneration) return

      const context = getContext(this) as common.UIAbilityContext
      this.cameraManager = camera.getCameraManager(context)
      const devices = this.cameraManager.getSupportedCameras()
      if (devices.length === 0) {
        throw new Error('系统没有枚举到摄像头，请检查 USB 独立供电')
      }

      const device = devices[0]
      const modes = this.cameraManager.getSupportedSceneModes(device)
      if (modes.indexOf(camera.SceneMode.NORMAL_VIDEO) < 0) {
        throw new Error('当前摄像头不支持 NORMAL_VIDEO 模式')
      }
      const capability = this.cameraManager.getSupportedOutputCapability(
        device, camera.SceneMode.NORMAL_VIDEO)
      const previewProfile = this.chooseProfile(capability.previewProfiles)
      const photoProfile = this.chooseProfile(capability.photoProfiles)
      const analysisProfile = this.chooseAnalysisProfile(capability.videoProfiles)

      this.cameraInput = this.cameraManager.createCameraInput(device)
      this.previewWidth = previewProfile.size.width
      this.previewHeight = previewProfile.size.height
      this.surfaceCaptureEnabled = false
      await this.cameraInput.open()
      if (!this.pageActive || startGeneration !== this.cameraStartGeneration) {
        await this.releasePipeline()
        return
      }
      this.captureSession = this.cameraManager.createSession<camera.VideoSession>(
        camera.SceneMode.NORMAL_VIDEO)

      if (this.enableContinuousYuv && analysisProfile) {
        this.analysisReceiver = image.createImageReceiver(
          analysisProfile.size.width, analysisProfile.size.height, analysisProfile.format, 3)
        const analysisSurfaceId = await this.analysisReceiver.getReceivingSurfaceId()
        this.analysisOutput = this.cameraManager.createVideoOutput(analysisProfile, analysisSurfaceId)
        this.analysisReceiver.on('imageArrival', (error) => {
          if (error) {
            hilog.warn(DOMAIN, TAG, 'Analysis frame callback failed: %{public}s', JSON.stringify(error))
            return
          }
          this.handleAnalysisFrame()
        })
      }

      this.captureSession.beginConfig()
      if (!this.captureSession.canAddInput(this.cameraInput)) {
        throw new Error('Camera session 拒绝摄像头输入')
      }
      this.captureSession.addInput(this.cameraInput)

      // Preview and analysis are independent outputs.  The previous branch
      // selected analysis *instead of* preview, leaving the XComponent
      // surface unbound whenever YUV was enabled.
      this.previewOutput = this.cameraManager.createPreviewOutput(previewProfile, surfaceId)
      if (!this.captureSession.canAddOutput(this.previewOutput)) {
        throw new Error('Camera session 拒绝预览输出')
      }
      this.captureSession.addOutput(this.previewOutput)

      let continuousAnalysis = false
      if (this.analysisOutput && this.captureSession.canAddOutput(this.analysisOutput)) {
        this.captureSession.addOutput(this.analysisOutput)
        continuousAnalysis = true
        this.surfaceCaptureEnabled = false
        if (analysisProfile) {
          hilog.info(DOMAIN, TAG, 'YUV analysis profile: %{public}dx%{public}d',
            analysisProfile.size.width, analysisProfile.size.height)
        }
      } else {
        try {
          if (this.analysisOutput) await this.analysisOutput.release()
        } catch (_error) {}
        try {
          if (this.analysisReceiver) await this.analysisReceiver.release()
        } catch (_error) {}
        this.analysisOutput = undefined
        this.analysisReceiver = undefined

        this.photoOutput = this.cameraManager.createPhotoOutput(photoProfile)
        this.photoOutput.on('photoAvailable', (error, photo) => {
          this.frameCaptureBusy = false
          if (this.completedDetectionCount < 5) {
            hilog.info(DOMAIN, TAG, 'Photo frame available: completed=%{public}d',
              this.completedDetectionCount)
          }
          if (error) {
            this.frameCaptureStartedAt = 0
            this.inferenceBusy = false
            hilog.error(DOMAIN, TAG, 'Photo callback error: %{public}s', JSON.stringify(error))
            this.scheduleNextDetection()
            return
          }
          this.processCameraPhoto(photo)
        })
        if (!this.captureSession.canAddOutput(this.photoOutput)) {
          throw new Error('Camera session 不支持连续 YUV 分析或 JPEG 抓拍')
        }
        this.captureSession.addOutput(this.photoOutput)
      }
      await this.captureSession.commitConfig()
      await this.captureSession.start()
      if (!this.pageActive || startGeneration !== this.cameraStartGeneration) {
        await this.releasePipeline()
        return
      }
      if (continuousAnalysis && this.analysisOutput) await this.analysisOutput.start()

      this.isCameraReady = true
      if (this.modelReady) {
        this.statusText = `摄像头已就绪 ${this.previewWidth}×${this.previewHeight}，正在实时检测`
        this.startDetectionLoop()
      } else {
        this.statusText = '摄像头预览已就绪，正在后台加载识别模型…'
      }
      hilog.info(DOMAIN, TAG, 'Camera ready: %{public}s, continuousYuv=%{public}s',
        device.cameraId, continuousAnalysis ? 'true' : 'false')
    } catch (error) {
      this.statusText = `摄像头启动失败：${(error as Error).message}`
      hilog.error(DOMAIN, TAG, 'Camera start failed: %{public}s', JSON.stringify(error))
      await this.releasePipeline()
    }
  }

  private startDetectionLoop(): void {
    this.stopDetectionLoop()
    this.detectionLoopActive = true
    if (!this.analysisReceiver) this.scheduleNextDetection(0)
  }

  private scheduleNextDetection(delayMs: number = DETECTION_MIN_INTERVAL_MS): void {
    if (!this.detectionLoopActive || !this.pageActive || !this.isCameraReady ||
      !this.modelReady || this.analysisReceiver || this.detectionTimerId !== -1) return
    const intervalMs = delayMs > 0 ? delayMs : DETECTION_MIN_INTERVAL_MS
    this.detectionTimerId = setInterval(() => {
      this.detectionTickCount += 1
      if (this.detectionTickCount <= 5 || this.detectionTickCount % 30 === 0) {
        hilog.info(DOMAIN, TAG,
          'Detection tick=%{public}d busy=%{public}s captureBusy=%{public}s completed=%{public}d',
          this.detectionTickCount, this.inferenceBusy ? 'true' : 'false',
          this.frameCaptureBusy ? 'true' : 'false', this.completedDetectionCount)
      }
      this.captureCameraFrame()
    }, intervalMs)
    hilog.info(DOMAIN, TAG, 'Detection timer started: intervalMs=%{public}d', intervalMs)
    if (delayMs === 0) this.captureCameraFrame()
  }

  private stopDetectionLoop(): void {
    this.detectionLoopActive = false
    if (this.detectionTimerId !== -1) {
      clearInterval(this.detectionTimerId)
      this.detectionTimerId = -1
    }
    this.inferenceBusy = false
    this.frameCaptureBusy = false
    this.frameCaptureStartedAt = 0
    this.analysisReadBusy = false
    this.lastDetectionFinishedAt = 0
  }

  private async handleAnalysisFrame(): Promise<void> {
    if (!this.analysisReceiver || this.analysisReadBusy) return
    this.analysisReadBusy = true
    let frame: image.Image | undefined = undefined
    try {
      frame = await this.analysisReceiver.readLatestImage()
    } catch (_error) {
      this.analysisReadBusy = false
      return
    }
    this.analysisReadBusy = false

    const now = Date.now()
    if (!this.detectionLoopActive || !this.pageActive || !this.isCameraReady ||
      !this.modelReady || this.inferenceBusy ||
      now - this.lastDetectionFinishedAt < DETECTION_MIN_INTERVAL_MS) {
      try {
        await frame.release()
      } catch (_error) {}
      return
    }

    this.inferenceBusy = true
    this.frameCaptureStartedAt = now
    await this.processCameraYuv(frame)
  }

  private async captureCameraFrame(): Promise<void> {
    if (!this.pageActive || !this.isCameraReady) return
    const now = Date.now()
    if (this.frameCaptureBusy) {
      if (this.frameCaptureStartedAt > 0 && now - this.frameCaptureStartedAt >= CAMERA_FRAME_TIMEOUT_MS) {
        this.statusText = '摄像头已被系统识别，但没有返回画面；请接到独立供电 USB Hub，重新插拔后返回重试'
        this.isCameraReady = false
        this.stopDetectionLoop()
      } else {
        this.scheduleNextDetection()
      }
      return
    }
    if (this.inferenceBusy) {
      this.scheduleNextDetection()
      return
    }
    if (this.surfaceCaptureEnabled && this.previewSurfaceId.length > 0) {
      await this.capturePreviewSurfaceFrame()
      return
    }
    if (!this.photoOutput) return
    this.inferenceBusy = true
    this.frameCaptureBusy = true
    this.frameCaptureStartedAt = now
    try {
      await this.photoOutput.capture({ quality: camera.QualityLevel.QUALITY_LEVEL_LOW })
    } catch (error) {
      this.inferenceBusy = false
      this.frameCaptureBusy = false
      this.frameCaptureStartedAt = 0
      hilog.warn(DOMAIN, TAG, 'Detection capture skipped: %{public}s', JSON.stringify(error))
      this.scheduleNextDetection()
    }
  }

  private async capturePreviewSurfaceFrame(): Promise<void> {
    let pixelMap: image.PixelMap | undefined = undefined
    this.inferenceBusy = true
    this.frameCaptureStartedAt = Date.now()
    try {
      pixelMap = await image.createPixelMapFromSurface(this.previewSurfaceId, {
        x: 0,
        y: 0,
        size: { width: this.previewWidth, height: this.previewHeight }
      })
      const result = await inferYoloPixelMap(pixelMap, 0.25, 0.45)
      if (this.pageActive) {
        const endToEndMs = Date.now() - this.frameCaptureStartedAt
        this.applyInferenceResult(result, endToEndMs)
      }
    } catch (error) {
      this.surfaceCaptureEnabled = false
      hilog.warn(DOMAIN, TAG,
        'Preview surface capture unavailable, falling back to JPEG: %{public}s', JSON.stringify(error))
      if (this.pageActive) this.statusText = '预览画面直接取帧不可用，已自动切换兼容模式'
    } finally {
      try {
        if (pixelMap) await pixelMap.release()
      } catch (_error) {}
      this.frameCaptureStartedAt = 0
      this.inferenceBusy = false
      this.lastDetectionFinishedAt = Date.now()
      this.completedDetectionCount += 1
      if (this.completedDetectionCount <= 5 || this.completedDetectionCount % 30 === 0) {
        hilog.info(DOMAIN, TAG, 'Detection completed=%{public}d', this.completedDetectionCount)
      }
      this.scheduleNextDetection()
    }
  }

  private async processCameraPhoto(photo: camera.Photo): Promise<void> {
    let source: image.ImageSource | undefined = undefined
    let pixelMap: image.PixelMap | undefined = undefined
    try {
      const component = await photo.main.getComponent(image.ComponentType.JPEG)
      source = image.createImageSource(component.byteBuffer)
      pixelMap = await source.createPixelMap({
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      })
      const result: NativeLiveInferenceResult = await inferYoloPixelMap(pixelMap, 0.25, 0.45)
      if (this.pageActive) {
        const endToEndMs = this.frameCaptureStartedAt > 0 ?
          Date.now() - this.frameCaptureStartedAt : result.totalMs
        this.applyInferenceResult(result, endToEndMs)
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Live inference failed: %{public}s', JSON.stringify(error))
      if (this.pageActive) this.statusText = `实时检测失败：${(error as Error).message}`
    } finally {
      try {
        if (pixelMap) await pixelMap.release()
      } catch (_error) {}
      try {
        if (source) await source.release()
      } catch (_error) {}
      try {
        photo.release().catch((error: Error) => {
          hilog.warn(DOMAIN, TAG, 'Photo release failed: %{public}s', JSON.stringify(error))
        })
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'Photo release start failed: %{public}s', JSON.stringify(error))
      }
      this.frameCaptureStartedAt = 0
      this.inferenceBusy = false
      this.lastDetectionFinishedAt = Date.now()
      this.completedDetectionCount += 1
      if (this.completedDetectionCount <= 5 || this.completedDetectionCount % 30 === 0) {
        hilog.info(DOMAIN, TAG, 'Detection completed=%{public}d', this.completedDetectionCount)
      }
      this.scheduleNextDetection()
    }
  }

  private async processCameraYuv(frame: image.Image): Promise<void> {
    try {
      const yComponent = await frame.getComponent(image.ComponentType.YUV_Y)
      const uComponent = await frame.getComponent(image.ComponentType.YUV_U)
      const vComponent = await frame.getComponent(image.ComponentType.YUV_V)
      const result = await inferYoloYuv420(
        new Uint8Array(yComponent.byteBuffer),
        new Uint8Array(uComponent.byteBuffer),
        new Uint8Array(vComponent.byteBuffer),
        frame.size.width, frame.size.height,
        yComponent.rowStride, uComponent.rowStride, vComponent.rowStride,
        uComponent.pixelStride, vComponent.pixelStride,
        0.25, 0.45)
      if (this.pageActive) {
        const endToEndMs = this.frameCaptureStartedAt > 0 ?
          Date.now() - this.frameCaptureStartedAt : result.totalMs
        this.applyInferenceResult(result, endToEndMs)
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Continuous YUV inference failed: %{public}s', JSON.stringify(error))
      if (this.pageActive) this.statusText = `连续画面检测失败：${(error as Error).message}`
    } finally {
      try {
        await frame.release()
      } catch (_error) {}
      this.frameCaptureStartedAt = 0
      this.inferenceBusy = false
      this.lastDetectionFinishedAt = Date.now()
    }
  }

  private drawDetections(): void {
    const context = this.overlayContext
    const width = context.width
    const height = context.height
    context.clearRect(0, 0, width, height)
    if (this.sceneMode === MonitoringScene.WORK && this.restrictedZone !== RestrictedZone.OFF) {
      const zoneX = this.restrictedZone === RestrictedZone.LEFT ? 0 : width * 0.72
      const zoneWidth = width * 0.28
      context.fillStyle = '#FF17452B'
      context.fillRect(zoneX, 0, zoneWidth, height)
      context.strokeStyle = '#FF5252'
      context.lineWidth = 3
      context.strokeRect(zoneX, 0, zoneWidth, height)
      context.font = '18px sans-serif'
      context.fillStyle = '#FF5252'
      context.fillText('禁区', zoneX + 12, height - 24)
    }
    context.lineWidth = 3
    context.font = '18px sans-serif'
    for (let index = 0; index < this.detections.length; index++) {
      const detection = this.detections[index]
      const mirroredX = Math.max(0, Math.min(1, this.mapDetectionX(detection)))
      const x = mirroredX * width
      const y = detection.y * height
      const boxWidth = detection.width * width
      const boxHeight = detection.height * height
      const label = COCO_LABELS[detection.classId] || `class ${detection.classId}`
      const text = `${label} ${(detection.score * 100).toFixed(0)}%`
      const highlighted = this.ruleHighlightLabels.indexOf(label) >= 0
      context.strokeStyle = highlighted ? '#FF5252' : '#00E5FF'
      context.strokeRect(x, y, boxWidth, boxHeight)
      const textWidth = Math.max(96, context.measureText(text).width + 12)
      const textY = Math.max(0, y - 26)
      context.fillStyle = highlighted ? '#6D1010E6' : '#001522D9'
      context.fillRect(x, textY, textWidth, 26)
      context.fillStyle = '#FFFFFF'
      context.fillText(text, x + 6, textY + 19)
    }
  }

  private async releasePipeline(): Promise<void> {
    if (this.pipelineReleaseInProgress) {
      await this.pipelineReleaseInProgress
      return
    }
    const releaseTask = this.releasePipelineImpl()
    this.pipelineReleaseInProgress = releaseTask
    try {
      await releaseTask
    } finally {
      if (this.pipelineReleaseInProgress === releaseTask) {
        this.pipelineReleaseInProgress = undefined
      }
    }
  }

  private async releasePipelineImpl(): Promise<void> {
    this.stopDetectionLoop()
    this.isCameraReady = false
    try {
      if (this.analysisOutput) await this.analysisOutput.stop()
    } catch (_error) {}
    try {
      if (this.captureSession) await this.captureSession.stop()
    } catch (_error) {}
    try {
      if (this.captureSession) await this.captureSession.release()
    } catch (_error) {}
    try {
      if (this.previewOutput) await this.previewOutput.release()
    } catch (_error) {}
    try {
      if (this.analysisOutput) await this.analysisOutput.release()
    } catch (_error) {}
    try {
      if (this.analysisReceiver) {
        await this.analysisReceiver.release()
      }
    } catch (_error) {}
    try {
      if (this.photoOutput) await this.photoOutput.release()
    } catch (_error) {}
    try {
      if (this.cameraInput) await this.cameraInput.close()
    } catch (_error) {}

    this.cameraInput = undefined
    this.previewOutput = undefined
    this.analysisOutput = undefined
    this.analysisReceiver = undefined
    this.photoOutput = undefined
    this.captureSession = undefined
  }

  build() {
    Stack() {
      XComponent({
        id: 'liveCameraPreview',
        type: 'surface',
        controller: this.previewController
      })
        .width('100%')
        .height('100%')
        .backgroundColor('#05070B')
        .onLoad(() => {
          this.previewSurfaceId = this.previewController.getXComponentSurfaceId()
          this.startCamera(this.previewSurfaceId)
        })

      Canvas(this.overlayContext)
        .width('100%')
        .height('100%')
        .backgroundColor('transparent')
        .hitTestBehavior(HitTestMode.None)
        .onReady(() => this.drawDetections())

      Column() {
        Row() {
          Button('返回')
            .height(42)
            .fontColor('#FFFFFF')
            .backgroundColor('#071522CC')
            .onClick(() => router.back())
          Blank()
          Column() {
            Text('YOLOv5 实时摄像头')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
            Text(`${this.detectionCount} 个目标 · ${this.inferenceText}`)
              .fontSize(13)
              .fontColor('#B7EFFF')
          }
          Blank()
          Row({ space: 8 }) {
            Circle()
              .width(12)
              .height(12)
              .fill(this.isCameraReady ? '#00E676' : '#607080')
            Text(this.isCameraReady ? 'LIVE' : 'WAIT')
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
          }
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 18, bottom: 14 })
        .backgroundColor('#020A12B8')

        Text(this.statusText)
          .fontSize(14)
          .fontColor('#E8F8FF')
          .backgroundColor('#020A1299')
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .borderRadius(6)
          .margin({ top: 12 })

        Row({ space: 8 }) {
          Button('工作')
            .height(38)
            .fontSize(14)
            .fontColor('#FFFFFF')
            .backgroundColor(this.sceneMode === MonitoringScene.WORK ? '#1677FF' : '#142333D9')
            .onClick(() => this.selectScene(MonitoringScene.WORK))
          Button('安检')
            .height(38)
            .fontSize(14)
            .fontColor('#FFFFFF')
            .backgroundColor(this.sceneMode === MonitoringScene.SECURITY ? '#1677FF' : '#142333D9')
            .onClick(() => this.selectScene(MonitoringScene.SECURITY))
          Button('公共')
            .height(38)
            .fontSize(14)
            .fontColor('#FFFFFF')
            .backgroundColor(this.sceneMode === MonitoringScene.PUBLIC ? '#1677FF' : '#142333D9')
            .onClick(() => this.selectScene(MonitoringScene.PUBLIC))
          if (this.sceneMode === MonitoringScene.WORK) {
            Button(`禁区：${this.zoneName()}`)
              .height(38)
              .fontSize(14)
              .fontColor('#FFFFFF')
              .backgroundColor(this.restrictedZone === RestrictedZone.OFF ? '#142333D9' : '#A92121E6')
              .onClick(() => this.cycleRestrictedZone())
          }
          Button(this.voiceEnabled ? '语音：开' : '语音：关')
            .height(38)
            .fontSize(14)
            .fontColor('#FFFFFF')
            .backgroundColor(this.voiceEnabled ? '#087F5BE6' : '#4D5966E6')
            .onClick(() => this.toggleVoice())
          Button('测试语音')
            .height(38)
            .fontSize(14)
            .fontColor('#FFFFFF')
            .backgroundColor('#6A38B8E6')
            .onClick(() => this.testVoicePlayback())
          Text(`${this.sceneName()}场景 · ${this.voiceStatus}`)
            .fontSize(13)
            .fontColor('#D8F4FF')
        }
        .height(54)
        .padding({ left: 14, right: 14 })
        .margin({ top: 8 })
        .backgroundColor('#020A12A8')
        .borderRadius(8)

        Row() {
          Column({ space: 5 }) {
            Text(this.rulePrimaryStatus)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
            Text(this.ruleSecondaryStatus)
              .fontSize(14)
              .fontColor('#D8F4FF')
            Text(this.ruleDetailStatus)
              .fontSize(14)
              .fontColor('#D8F4FF')
          }
          .width(440)
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .backgroundColor('#071522D9')
          .borderRadius(8)

          Blank()

          if (this.latestAlertTitle.length > 0) {
            Column({ space: 4 }) {
              Text(this.latestAlertTitle)
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor('#FFFFFF')
              Text(this.latestAlertMessage)
                .fontSize(14)
                .fontColor('#FFFFFF')
            }
            .width(430)
            .alignItems(HorizontalAlign.Start)
            .padding({ left: 18, right: 18, top: 12, bottom: 12 })
            .backgroundColor(this.latestAlertSeverity >= 2 ? '#B71C1CEB' : '#B05A00EB')
            .borderRadius(8)
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8 })

        Blank()

        Row({ space: 8 }) {
          Circle()
            .width(10)
            .height(10)
            .fill(this.isCameraReady ? '#00E676' : '#607080')
          Text(this.isCameraReady ? '实时检测中' : '正在准备摄像头')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
        }
        .height(48)
        .padding({ left: 22, right: 22 })
        .backgroundColor('#071522CC')
        .borderRadius(24)
        .margin({ bottom: 28 })
        .hitTestBehavior(HitTestMode.None)
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#05070B')
  }
}
