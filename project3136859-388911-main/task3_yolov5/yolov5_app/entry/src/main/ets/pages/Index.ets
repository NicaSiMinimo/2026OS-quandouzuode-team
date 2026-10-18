import { hilog } from '@kit.PerformanceAnalysisKit';
import http from '@ohos.net.http';
import { router } from '@kit.ArkUI';
import photoAccessHelper from '@ohos.file.photoAccessHelper';
import fs from '@ohos.file.fs';
import { common } from '@kit.AbilityKit';
import { display } from '@kit.ArkUI';
import { getYoloModelInfo, initializeYoloAsync, YoloModelInfo } from '../native/YoloNativeBridge';

const DOMAIN = 0x0000;
const TAG = 'Index';
const SERVER = 'http://127.0.0.1:5000';

interface ProgressResult {
  current: number; total: number; status: string; message: string;
}
interface ResultPair {
  original: string; detected: string;
}

// ── 配色 ─────────────────────────────────────────────────
const C_TEXT = '#E0E0F0';
const C_DIM = '#8080B0';
const C_ACCENT = '#4A90FF';
const C_ACTIVE = '#00E5FF';
const C_SUCCESS = '#00E676';

@Entry
@Component
struct Index {
  @State selectedUris: string[] = [];
  @State selectedNames: string[] = [];
  @State isRecognizing: boolean = false;
  @State progressValue: number = 0;
  @State progressTotal: number = 0;
  @State progressCurrent: number = 0;
  @State statusText: string = '请选择图片';
  @State isDone: boolean = false;
  @State cubeAngleX: number = 0;
  @State cubeAngleY: number = 0;
  @State cubeAngleZ: number = 0;
  @State showCube: boolean = false;
  @State canvasW: number = 400;
  @State canvasH: number = 600;

  private timerId: number = -1;
  private animTimerId: number = -1;
  private cubeSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private cubeCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.cubeSettings);
  private videoController: VideoController = new VideoController();

  aboutToAppear(): void {
    this.startAnimation();
    try {
      const dis = display.getDefaultDisplaySync();
      this.canvasW = dis.width;
      this.canvasH = dis.height;
    } catch (_e) { this.canvasW = 400; this.canvasH = 600; }
    this.initializeNativeYolo();
  }

  aboutToDisappear(): void { this.clearTimer(); this.stopAnimation(); }

  private clearTimer(): void {
    if (this.timerId !== -1) { clearInterval(this.timerId); this.timerId = -1; }
  }

  private startAnimation(): void {
    this.animTimerId = setInterval(() => {
      if (this.showCube) {
        this.cubeAngleX += 0.02; this.cubeAngleY += 0.03; this.cubeAngleZ += 0.01;
        if (this.cubeCtx) {
          const w = this.cubeCtx.width;
          const h = this.cubeCtx.height;
          this.cubeCtx.clearRect(0, 0, w, h);
          this.drawCube(this.cubeCtx, w, h);
        }
      }
    }, 16);
  }

  private stopAnimation(): void {
    if (this.animTimerId !== -1) { clearInterval(this.animTimerId); this.animTimerId = -1; }
  }

  private goHome(): void {
    try { (getContext(this) as common.UIAbilityContext).terminateSelf(); } catch (_e) {}
  }

  private async initializeNativeYolo(): Promise<void> {
    this.statusText = 'NAPI 正在后台加载模型…';
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const info: YoloModelInfo = await initializeYoloAsync(context.resourceManager, 0);
      this.statusText = `NAPI 已就绪 · 输入 ${info.inputByteSizes[0] || 0} 字节`;
      hilog.info(DOMAIN, TAG, 'YOLO_NAPI_READY %{public}s', JSON.stringify(info));
    } catch (error) {
      const info: YoloModelInfo = getYoloModelInfo();
      const message: string = info.lastError.length > 0 ? info.lastError : (error as Error).message;
      if (message.includes('connect 127.0.0.1:5001 failed')) {
        this.statusText = 'CANN 推理服务未启动：' + message;
      } else {
        this.statusText = 'CANN 推理后端初始化失败：' + message;
      }
      hilog.error(DOMAIN, TAG, 'YOLO_NAPI_FAILED %{public}s', JSON.stringify(info));
    }
  }

  // ── 3D 旋转 + 投影 ────────────────────────────────────
  private rotatePoint(x: number, y: number, z: number): number[] {
    const cosX = Math.cos(this.cubeAngleX), sinX = Math.sin(this.cubeAngleX);
    const cosY = Math.cos(this.cubeAngleY), sinY = Math.sin(this.cubeAngleY);
    const cosZ = Math.cos(this.cubeAngleZ), sinZ = Math.sin(this.cubeAngleZ);
    let t: number;
    t = y * cosX - z * sinX; z = y * sinX + z * cosX; y = t;
    t = x * cosY + z * sinY; z = -x * sinY + z * cosY; x = t;
    t = x * cosZ - y * sinZ; y = x * sinZ + y * cosZ; x = t;
    return [x, y, z];
  }

  private projPoint(x: number, y: number, z: number, cx: number, cy: number, dist: number): number[] {
    const scale = dist / (dist + z * 0.005);
    return [cx + x * scale, cy + y * scale, z];
  }

  // ── 魔方绘制（3×3×3） ─────────────────────────────────
  private drawCube(ctx: CanvasRenderingContext2D, w: number, h: number): void {
    const cx = w / 2;
    const cy = h / 2;
    const cubeSize = 32;
    const gap = 2;
    const step = cubeSize * 2 + gap;
    const dist = 800;

    const faceColorTop = '#4A90FFCC';
    const faceColorBottom = '#4A90FFCC';
    const faceColorFront = '#4A90FFCC';
    const faceColorBack = '#4A90FFCC';
    const faceColorLeft = '#4A90FFCC';
    const faceColorRight = '#4A90FFCC';
    const edgeColor = '#4A90FF80';

    const cubes: number[][] = [];
    for (let ix = -1; ix <= 1; ix++) {
      for (let iy = -1; iy <= 1; iy++) {
        for (let iz = -1; iz <= 1; iz++) {
          if (ix === 0 && iy === 0 && iz === 0) continue;
          cubes.push([ix * step, iy * step, iz * step]);
        }
      }
    }

    const s = cubeSize;
    const faces: number[][][] = [
      [[-s,-s,s], [s,-s,s], [s,s,s], [-s,s,s]],
      [[s,-s,-s], [-s,-s,-s], [-s,s,-s], [s,s,-s]],
      [[-s,-s,-s], [-s,-s,s], [-s,s,s], [-s,s,-s]],
      [[s,-s,s], [s,-s,-s], [s,s,-s], [s,s,s]],
      [[-s,-s,-s], [s,-s,-s], [s,-s,s], [-s,-s,s]],
      [[-s,s,s], [s,s,s], [s,s,-s], [-s,s,-s]],
    ];

    const faceColors: string[] = [faceColorFront, faceColorBack, faceColorLeft, faceColorRight, faceColorTop, faceColorBottom];

    const isOuterFace = (cubePos: number[], faceIdx: number): boolean => {
      const px = cubePos[0] / step;
      const py = cubePos[1] / step;
      const pz = cubePos[2] / step;
      if (faceIdx === 0 && pz === 1) return true;
      if (faceIdx === 1 && pz === -1) return true;
      if (faceIdx === 2 && px === -1) return true;
      if (faceIdx === 3 && px === 1) return true;
      if (faceIdx === 4 && py === -1) return true;
      if (faceIdx === 5 && py === 1) return true;
      return false;
    };

    interface DrawFace {
      verts: number[][];
      z: number;
      color: string;
    }
    const drawFaces: DrawFace[] = [];

    for (let ci = 0; ci < cubes.length; ci++) {
      const cube = cubes[ci];
      for (let fi = 0; fi < 6; fi++) {
        if (!isOuterFace(cube, fi)) continue;
        const face = faces[fi];
        const projVerts: number[][] = [];
        let avgZ = 0;
        for (let vi = 0; vi < 4; vi++) {
          const worldX = cube[0] + face[vi][0];
          const worldY = cube[1] + face[vi][1];
          const worldZ = cube[2] + face[vi][2];
          const rotated = this.rotatePoint(worldX, worldY, worldZ);
          const projected = this.projPoint(rotated[0], rotated[1], rotated[2], cx, cy, dist);
          projVerts.push(projected);
          avgZ += projected[2];
        }
        avgZ /= 4;
        drawFaces.push({ verts: projVerts, z: avgZ, color: faceColors[fi] });
      }
    }

    for (let i = 0; i < drawFaces.length - 1; i++) {
      for (let j = i + 1; j < drawFaces.length; j++) {
        if (drawFaces[i].z < drawFaces[j].z) {
          const tmp = drawFaces[i]; drawFaces[i] = drawFaces[j]; drawFaces[j] = tmp;
        }
      }
    }

    for (let i = 0; i < drawFaces.length; i++) {
      const df = drawFaces[i];
      ctx.beginPath();
      ctx.moveTo(df.verts[0][0], df.verts[0][1]);
      ctx.lineTo(df.verts[1][0], df.verts[1][1]);
      ctx.lineTo(df.verts[2][0], df.verts[2][1]);
      ctx.lineTo(df.verts[3][0], df.verts[3][1]);
      ctx.closePath();
      ctx.fillStyle = df.color;
      ctx.fill();
      ctx.strokeStyle = edgeColor;
      ctx.lineWidth = 1.5;
      ctx.stroke();
    }
  }

  // ── 选择图片 ────────────────────────────────────────────
  private async pickImages(): Promise<void> {
    try {
      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      const options: photoAccessHelper.PhotoSelectOptions = {
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE, maxSelectNumber: 99
      };
      const result: photoAccessHelper.PhotoSelectResult = await photoPicker.select(options);
      if (!result || !result.photoUris || result.photoUris.length === 0) return;

      const uris: string[] = result.photoUris;
      const names: string[] = [];
      const context = getContext(this);
      const tempDir: string = context.filesDir + '/temp_images/';
      try {
        const files: string[] = fs.listFileSync(tempDir);
        for (const f of files) fs.unlinkSync(tempDir + f);
      } catch (_e) { fs.mkdirSync(tempDir); }

      const cleanReq = http.createHttp();
      await cleanReq.request(`${SERVER}/clean`, { method: http.RequestMethod.POST, readTimeout: 5000 });
      cleanReq.destroy();

      let uploadedCount: number = 0;
      for (const uri of uris) {
        try {
          const decoded: string = decodeURIComponent(uri);
          const fileName: string = decoded.substring(decoded.lastIndexOf('/') + 1);
          const srcFile = fs.openSync(uri, fs.OpenMode.READ_ONLY);
          const stat = fs.statSync(srcFile.fd);
          const fileSize: number = stat.size;
          const buf = new ArrayBuffer(fileSize);
          fs.readSync(srcFile.fd, buf, { length: fileSize });
          fs.closeSync(srcFile);

          const httpRequest = http.createHttp();
          const boundary: string = '----FormBoundary' + Date.now();
          const header: string = '--' + boundary + '\r\nContent-Disposition: form-data; name="file"; filename="' + fileName + '"\r\nContent-Type: application/octet-stream\r\n\r\n';
          const footer: string = '\r\n--' + boundary + '--\r\n';
          const headerBuf = new ArrayBuffer(header.length);
          const headerView = new Uint8Array(headerBuf);
          for (let i = 0; i < header.length; i++) headerView[i] = header.charCodeAt(i);
          const footerBuf = new ArrayBuffer(footer.length);
          const footerView = new Uint8Array(footerBuf);
          for (let i = 0; i < footer.length; i++) footerView[i] = footer.charCodeAt(i);
          const bodyBuf = new ArrayBuffer(headerBuf.byteLength + buf.byteLength + footerBuf.byteLength);
          new Uint8Array(bodyBuf).set(new Uint8Array(headerBuf), 0);
          new Uint8Array(bodyBuf).set(new Uint8Array(buf), headerBuf.byteLength);
          new Uint8Array(bodyBuf).set(new Uint8Array(footerBuf), headerBuf.byteLength + buf.byteLength);
          await httpRequest.request(SERVER + '/upload', {
            method: http.RequestMethod.POST,
            header: { 'Content-Type': 'multipart/form-data; boundary=' + boundary },
            extraData: bodyBuf, readTimeout: 30000
          });
          httpRequest.destroy();
          names.push(fileName); uploadedCount++;
          hilog.info(DOMAIN, TAG, 'Uploaded: %{public}s (%{public}d bytes)', fileName, fileSize);
        } catch (e) { hilog.error(DOMAIN, TAG, 'Failed upload: %{public}s', JSON.stringify(e)); }
      }

      this.selectedUris = uris;
      this.selectedNames = names;
      this.statusText = '已选择 ' + uploadedCount + ' 张图片';
      this.isDone = false; this.progressValue = 0;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'pickImages error: %{public}s', JSON.stringify(e));
      this.statusText = '选择图片失败';
    }
  }

  // ── 轮询进度 ──────────────────────────────────────────
  private startProgressPolling(): void {
    this.timerId = setInterval(async () => {
      try {
        const hr = http.createHttp();
        const res = await hr.request(SERVER + '/progress', { method: http.RequestMethod.GET, readTimeout: 5000 });
        hr.destroy();
        const d = JSON.parse(res.result as string) as ProgressResult;
        this.progressCurrent = d.current; this.progressTotal = d.total;
        if (d.total > 0) this.progressValue = Math.floor((d.current / d.total) * 100);
        if (d.status === 'done' || d.status === 'error') {
          this.clearTimer(); this.isRecognizing = false; this.showCube = false;
          this.videoController.start();
          if (d.status === 'done') {
            this.progressValue = 100; this.isDone = true;
            this.statusText = '识别完成 ' + d.total + ' 张图片';
          } else { this.statusText = '识别失败'; }
        }
      } catch (_e) {}
    }, 1000);
  }

  private async startRecognition(): Promise<void> {
    if (this.selectedUris.length === 0) { this.statusText = '请先选择图片！'; return; }
    this.isRecognizing = true; this.isDone = false; this.showCube = true;
    this.videoController.pause();
    this.progressValue = 0; this.progressCurrent = 0; this.progressTotal = this.selectedUris.length;
    this.statusText = '识别中...';
    try {
      const hr = http.createHttp();
      const res = await hr.request(SERVER + '/start', {
        method: http.RequestMethod.POST, readTimeout: 10000,
        header: { 'Content-Type': 'application/json' }, extraData: JSON.stringify({})
      });
      hr.destroy();
      const r = JSON.parse(res.result as string) as Record<string, Object>;
      if (r.msg === 'started') { this.statusText = '识别已启动...'; this.startProgressPolling(); }
      else { this.isRecognizing = false; this.showCube = false; this.videoController.start(); this.statusText = '启动失败'; }
    } catch (e) {
      this.isRecognizing = false; this.showCube = false; this.videoController.start();
      this.statusText = '请求失败'; hilog.error(DOMAIN, TAG, 'startRecognition error: %{public}s', JSON.stringify(e));
    }
  }

  private async viewResults(): Promise<void> {
    try {
      const hr = http.createHttp();
      const res = await hr.request(SERVER + '/results', { method: http.RequestMethod.GET, readTimeout: 10000 });
      hr.destroy();
      const results = JSON.parse(res.result as string) as ResultPair[];
      AppStorage.setOrCreate('resultPairs', JSON.stringify(results));
      AppStorage.setOrCreate('serverUrl', SERVER);
      AppStorage.setOrCreate('urlPrefix', '/output/');
      router.pushUrl({ url: 'pages/ResultView' });
    } catch (e) { hilog.error(DOMAIN, TAG, 'viewResults error: %{public}s', JSON.stringify(e)); }
  }

  private async viewSaved(): Promise<void> {
    try {
      const hr = http.createHttp();
      const res = await hr.request(SERVER + '/long_term', { method: http.RequestMethod.GET, readTimeout: 10000 });
      hr.destroy();
      const results = JSON.parse(res.result as string) as ResultPair[];
      AppStorage.setOrCreate('resultPairs', JSON.stringify(results));
      AppStorage.setOrCreate('serverUrl', SERVER);
      AppStorage.setOrCreate('urlPrefix', '/long_term_files/');
      router.pushUrl({ url: 'pages/ResultView' });
    } catch (e) { hilog.error(DOMAIN, TAG, 'viewSaved error: %{public}s', JSON.stringify(e)); }
  }

  build() {
    Stack() {
      // ── 视频背景 ────────────────────────────────────────
      Video({
        src: $rawfile('background.mp4'),
        controller: this.videoController
      })
        .width('100%').height('100%')
        .objectFit(ImageFit.Cover)
        .autoPlay(true).loop(true).muted(true)
        .controls(false)
        .backgroundColor('#151419')

      // ── UI 浮层 ──────────────────────────────────────
      Column() {
        // 顶部栏
        Row() {
          Text('YOLOv5目标检测').fontSize(20).fontFamily('monospace').fontWeight(FontWeight.Bold)
            .fontColor(C_TEXT).letterSpacing(2)
          Blank()

          Button() { Text('⌂').fontSize(22).fontColor(C_TEXT) }
            .width(44).height(44).borderRadius(22)
            .backgroundColor('#0A0A2080').border({ width: 1, color: '#2A2A5A80' })
            .onClick(() => this.goHome())
        }.width('100%').padding({ left: 20, right: 20, top: 36 })

        Text(this.statusText).fontSize(13).fontColor(C_DIM)
          .margin({ top: 8 }).padding({ left: 20 }).width('100%')

        Button('实时摄像头检测')
          .fontSize(15).fontWeight(FontWeight.Bold).fontColor('#0B0D2E')
          .height(50).width('100%').borderRadius(10)
          .backgroundColor(C_ACTIVE)
          .margin({ top: 10 })
          .onClick(() => router.pushUrl({ url: 'pages/LiveCamera' }))
          .padding({ left: 20, right: 20 })

        Row({ space: 8 }) {
          Button('选择图片')
            .fontSize(15).fontWeight(FontWeight.Bold).fontColor('#0B0D2E')
            .height(50).layoutWeight(1).borderRadius(10)
            .backgroundColor(C_ACCENT)
            .opacity(0.5)
            .enabled(!this.isRecognizing)
            .onClick(() => this.pickImages())

          Button('查看保存记录')
            .fontSize(15).fontWeight(FontWeight.Bold).fontColor('#0B0D2E')
            .height(50).layoutWeight(1).borderRadius(10)
            .backgroundColor(C_ACCENT)
            .opacity(0.5)
            .onClick(() => this.viewSaved())
        }.width('100%').padding({ left: 20, right: 20, top: 10 })

        // 图片预览（固定最大高度 260，内部滚动）
        if (this.selectedUris.length > 0) {
          Column() {
            Row() {
              Text('已选图片').fontSize(10).fontFamily('monospace').fontWeight(FontWeight.Bold)
                .fontColor(C_DIM).letterSpacing(2)
              Blank()
              Text(this.selectedUris.length + ' 张').fontSize(10).fontFamily('monospace')
                .fontColor(C_ACCENT).letterSpacing(1)
            }.width('100%').padding({ left: 14, right: 14, top: 10, bottom: 8 })

            Scroll() {
              Grid() {
                ForEach(this.selectedUris, (uri: string, index: number) => {
                  GridItem() {
                    Stack({ alignContent: Alignment.BottomStart }) {
                      Image(uri).width('100%').height('100%')
                        .objectFit(ImageFit.Contain).borderRadius(6).backgroundColor('#0A0A20')
                      Text(String(index + 1).padStart(2, '0'))
                        .fontSize(9).fontFamily('monospace').fontWeight(FontWeight.Bold)
                        .fontColor(C_ACTIVE).backgroundColor('#0B0D2ECC')
                        .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                        .borderRadius(2).margin({ left: 4, bottom: 4 })
                    }.width('100%').height(120)
                  }
                })
              }
              .columnsTemplate('1fr 1fr 1fr 1fr 1fr')
              .columnsGap(6).rowsGap(6)
              .width('100%')
              .padding({ left: 10, right: 10, bottom: 10 })
            }
            .scrollBar(BarState.Auto)
            .width('100%')
          }
          .width('100%').height(380).margin({ top: 8, left: 16, right: 16 })
        }

        Blank()

        // 底部按钮
        Column({ space: 8 }) {
          Button(this.isRecognizing ? '识别中...' : '开始识别')
            .width('100%').height(50).borderRadius(10)
            .fontSize(16).fontWeight(FontWeight.Bold).fontColor('#0B0D2E')
            .backgroundColor(this.isRecognizing ? C_DIM : C_ACCENT)
            .enabled(!this.isRecognizing && !this.isDone && this.selectedUris.length > 0)
            .onClick(() => this.startRecognition())

          if (this.isDone) {
            Button('查看检测结果')
              .width('100%').height(50).borderRadius(10)
              .fontSize(16).fontWeight(FontWeight.Bold).fontColor('#0B0D2E')
              .backgroundColor(C_SUCCESS)
              .onClick(() => this.viewResults())
          }
        }.width('100%').padding({ left: 20, right: 20, bottom: 36 })
      }.width('100%').height('100%')

      // ── 魔方覆盖层（在 UI 层之后渲染，确保在最上层）──
      if (this.showCube) {
        Column()
          .width('100%').height('100%')
          .backgroundColor('#505050DD')

        Canvas(this.cubeCtx)
          .width('100%').height('100%')
          .backgroundColor('transparent')
          .onReady(() => {
            this.canvasW = this.cubeCtx.width;
            this.canvasH = this.cubeCtx.height;
            this.drawCube(this.cubeCtx, this.canvasW, this.canvasH);
          })
      }
    }.width('100%').height('100%')
  }
}
