export enum MonitoringScene {
  WORK = 0,
  SECURITY = 1,
  PUBLIC = 2
}

export enum RestrictedZone {
  OFF = 0,
  LEFT = 1,
  RIGHT = 2
}

export class RuleDetection {
  classId: number
  label: string
  score: number
  x: number
  y: number
  width: number
  height: number

  constructor(classId: number, label: string, score: number,
    x: number, y: number, width: number, height: number) {
    this.classId = classId
    this.label = label
    this.score = score
    this.x = x
    this.y = y
    this.width = width
    this.height = height
  }

  centerX(): number {
    return this.x + this.width / 2
  }

  centerY(): number {
    return this.y + this.height / 2
  }
}

export class RuleAlert {
  key: string
  title: string
  message: string
  audioFile: string
  severity: number

  constructor(key: string, title: string, message: string, audioFile: string, severity: number) {
    this.key = key
    this.title = title
    this.message = message
    this.audioFile = audioFile
    this.severity = severity
  }
}

export class RuleEvaluation {
  alerts: RuleAlert[] = []
  primaryStatus: string = ''
  secondaryStatus: string = ''
  detailStatus: string = ''
  activeKeys: string[] = []
  highlightLabels: string[] = []
}

class BaggageTrack {
  id: number
  label: string
  x: number
  y: number
  width: number
  height: number
  anchorX: number
  anchorY: number
  firstStationaryAt: number
  lastSeenAt: number
  lastNearPersonAt: number
  alerted: boolean = false

  constructor(id: number, detection: RuleDetection, now: number, nearPerson: boolean) {
    this.id = id
    this.label = detection.label
    this.x = detection.x
    this.y = detection.y
    this.width = detection.width
    this.height = detection.height
    this.anchorX = detection.centerX()
    this.anchorY = detection.centerY()
    this.firstStationaryAt = now
    this.lastSeenAt = now
    this.lastNearPersonAt = now
    if (!nearPerson) this.lastNearPersonAt = now
  }

  centerX(): number {
    return this.x + this.width / 2
  }

  centerY(): number {
    return this.y + this.height / 2
  }
}

const EQUIPMENT_LABELS: string[] = ['tv', 'laptop', 'keyboard', 'mouse']
const BAGGAGE_LABELS: string[] = ['backpack', 'handbag', 'suitcase']
const SHARP_LABELS: string[] = ['knife', 'scissors']
const FOOD_DRINK_LABELS: string[] = [
  'bottle', 'wine glass', 'cup', 'fork', 'spoon', 'bowl', 'banana', 'apple',
  'sandwich', 'orange', 'broccoli', 'carrot', 'hot dog', 'pizza', 'donut', 'cake'
]
const ANIMAL_LABELS: string[] = ['bird', 'cat', 'dog']

export class SceneRuleEngine {
  private scene: MonitoringScene = MonitoringScene.WORK
  private restrictedZone: RestrictedZone = RestrictedZone.RIGHT
  private conditionSince: Map<string, number> = new Map<string, number>()
  private conditionLastTrue: Map<string, number> = new Map<string, number>()
  private cooldownUntil: Map<string, number> = new Map<string, number>()
  private dutyState: number = 0
  private presenceSince: number = 0
  private absenceSince: number = 0
  private equipmentCalibrationStartedAt: number = 0
  private equipmentCalibrated: boolean = false
  private equipmentSeenCount: Map<string, number> = new Map<string, number>()
  private equipmentLastSeen: Map<string, number> = new Map<string, number>()
  private expectedEquipment: string[] = []
  private baggageTracks: BaggageTrack[] = []
  private nextTrackId: number = 1

  setScene(scene: MonitoringScene, now: number): void {
    if (this.scene === scene && this.equipmentCalibrationStartedAt !== 0) return
    this.scene = scene
    this.reset(now)
  }

  getScene(): MonitoringScene {
    return this.scene
  }

  setRestrictedZone(zone: RestrictedZone): void {
    this.restrictedZone = zone
    this.conditionSince.delete('work_intrusion')
    this.conditionLastTrue.delete('work_intrusion')
  }

  getRestrictedZone(): RestrictedZone {
    return this.restrictedZone
  }

  reset(now: number): void {
    this.conditionSince.clear()
    this.conditionLastTrue.clear()
    this.cooldownUntil.clear()
    this.dutyState = 0
    this.presenceSince = 0
    this.absenceSince = now
    this.equipmentCalibrationStartedAt = now
    this.equipmentCalibrated = false
    this.equipmentSeenCount.clear()
    this.equipmentLastSeen.clear()
    this.expectedEquipment = []
    this.baggageTracks = []
    this.nextTrackId = 1
  }

  evaluate(detections: RuleDetection[], now: number): RuleEvaluation {
    if (this.equipmentCalibrationStartedAt === 0) this.reset(now)
    if (this.scene === MonitoringScene.SECURITY) {
      return this.evaluateSecurity(detections, now)
    }
    if (this.scene === MonitoringScene.PUBLIC) {
      return this.evaluatePublic(detections, now)
    }
    return this.evaluateWork(detections, now)
  }

  private filterByLabel(detections: RuleDetection[], labels: string[], minimumScore: number): RuleDetection[] {
    const matches: RuleDetection[] = []
    for (let index = 0; index < detections.length; index++) {
      const detection = detections[index]
      if (detection.score >= minimumScore && labels.indexOf(detection.label) >= 0) {
        matches.push(detection)
      }
    }
    return matches
  }

  private addUnique(values: string[], value: string): void {
    if (values.indexOf(value) < 0) values.push(value)
  }

  private updateCondition(key: string, active: boolean, now: number,
    confirmMs: number, toleratedGapMs: number, cooldownMs: number): boolean {
    if (active) {
      this.conditionLastTrue.set(key, now)
      if (!this.conditionSince.has(key)) this.conditionSince.set(key, now)
    } else {
      const lastTrue = this.conditionLastTrue.get(key)
      if (lastTrue === undefined || now - lastTrue > toleratedGapMs) {
        this.conditionSince.delete(key)
        this.conditionLastTrue.delete(key)
        return false
      }
    }

    const since = this.conditionSince.get(key)
    if (since === undefined || now - since < confirmMs) return false
    const cooldown = this.cooldownUntil.get(key)
    if (cooldown !== undefined && now < cooldown) return false
    this.cooldownUntil.set(key, now + cooldownMs)
    return true
  }

  private isPhoneAssociatedWithPerson(phone: RuleDetection, people: RuleDetection[]): boolean {
    const phoneX = phone.centerX()
    const phoneY = phone.centerY()
    for (let index = 0; index < people.length; index++) {
      const person = people[index]
      const marginX = Math.max(0.04, person.width * 0.12)
      const marginY = Math.max(0.04, person.height * 0.08)
      const insideX = phoneX >= person.x - marginX &&
        phoneX <= person.x + person.width + marginX
      const insideUpperBody = phoneY >= person.y - marginY &&
        phoneY <= person.y + person.height * 0.78
      if (insideX && insideUpperBody) return true
    }
    return false
  }

  private isPersonInsideRestrictedZone(person: RuleDetection): boolean {
    if (this.restrictedZone === RestrictedZone.OFF) return false
    const centerX = person.centerX()
    if (this.restrictedZone === RestrictedZone.LEFT) return centerX <= 0.28
    return centerX >= 0.72
  }

  private equipmentChineseName(label: string): string {
    if (label === 'tv') return '显示器'
    if (label === 'laptop') return '笔记本电脑'
    if (label === 'keyboard') return '键盘'
    if (label === 'mouse') return '鼠标'
    return label
  }

  private updateEquipmentBaseline(detections: RuleDetection[], now: number): string[] {
    const seenNow: string[] = []
    for (let index = 0; index < detections.length; index++) {
      const detection = detections[index]
      if (detection.score < 0.30 || EQUIPMENT_LABELS.indexOf(detection.label) < 0) continue
      this.addUnique(seenNow, detection.label)
      this.equipmentLastSeen.set(detection.label, now)
      if (!this.equipmentCalibrated) {
        const oldCount = this.equipmentSeenCount.get(detection.label)
        this.equipmentSeenCount.set(detection.label, (oldCount === undefined ? 0 : oldCount) + 1)
      }
    }

    if (!this.equipmentCalibrated && now - this.equipmentCalibrationStartedAt >= 12000) {
      this.expectedEquipment = []
      for (let index = 0; index < EQUIPMENT_LABELS.length; index++) {
        const label = EQUIPMENT_LABELS[index]
        const count = this.equipmentSeenCount.get(label)
        if (count !== undefined && count >= 3) this.expectedEquipment.push(label)
      }
      this.equipmentCalibrated = true
    }
    return seenNow
  }

  private evaluateWork(detections: RuleDetection[], now: number): RuleEvaluation {
    const evaluation = new RuleEvaluation()
    const people = this.filterByLabel(detections, ['person'], 0.30)
    const phones = this.filterByLabel(detections, ['cell phone'], 0.22)
    const personPresent = people.length > 0

    if (personPresent) {
      this.absenceSince = 0
      if (this.presenceSince === 0) this.presenceSince = now
      if (now - this.presenceSince >= 1200 && this.dutyState !== 1) {
        this.dutyState = 1
        evaluation.alerts.push(new RuleAlert('work_on_duty', '人员到岗',
          `检测到 ${people.length} 人进入工作区域`, 'work_on_duty.mp3', 0))
      }
    } else {
      this.presenceSince = 0
      if (this.absenceSince === 0) this.absenceSince = now
      if (now - this.absenceSince >= 10000 && this.dutyState !== 2) {
        this.dutyState = 2
        evaluation.alerts.push(new RuleAlert('work_off_duty', '人员离岗',
          '工作区域持续无人，请及时确认', 'work_off_duty.mp3', 1))
      }
    }

    const tooManyPeople = people.length > 1
    if (tooManyPeople) {
      evaluation.activeKeys.push('work_people_abnormal')
      this.addUnique(evaluation.highlightLabels, 'person')
    }
    if (this.updateCondition('work_people_abnormal', tooManyPeople, now, 1800, 900, 20000)) {
      evaluation.alerts.push(new RuleAlert('work_people_abnormal', '人数异常',
        `工作区域检测到 ${people.length} 人，超过上限 1 人`, 'work_people_abnormal.mp3', 1))
    }

    let intrusion = false
    for (let index = 0; index < people.length; index++) {
      if (this.isPersonInsideRestrictedZone(people[index])) {
        intrusion = true
        break
      }
    }
    if (intrusion) {
      evaluation.activeKeys.push('work_intrusion')
      this.addUnique(evaluation.highlightLabels, 'person')
    }
    if (this.updateCondition('work_intrusion', intrusion, now, 1000, 700, 15000)) {
      evaluation.alerts.push(new RuleAlert('work_intrusion', '禁区闯入',
        '检测到人员进入标记禁区，请立即确认', 'work_intrusion.mp3', 2))
    }

    let phoneUse = false
    for (let index = 0; index < phones.length; index++) {
      if (this.isPhoneAssociatedWithPerson(phones[index], people)) {
        phoneUse = true
        break
      }
    }
    if (phoneUse) {
      evaluation.activeKeys.push('work_phone')
      this.addUnique(evaluation.highlightLabels, 'cell phone')
    }
    if (this.updateCondition('work_phone', phoneUse, now, 1200, 1000, 20000)) {
      evaluation.alerts.push(new RuleAlert('work_phone', '疑似使用手机',
        '手机与人员上半身持续关联，请人工确认', 'work_phone.mp3', 1))
    }

    this.updateEquipmentBaseline(detections, now)
    const missingEquipment: string[] = []
    if (this.equipmentCalibrated) {
      for (let index = 0; index < this.expectedEquipment.length; index++) {
        const label = this.expectedEquipment[index]
        const lastSeen = this.equipmentLastSeen.get(label)
        if (lastSeen === undefined || now - lastSeen > 8000) {
          missingEquipment.push(label)
          this.addUnique(evaluation.highlightLabels, label)
        }
      }
    }
    const equipmentMissing = missingEquipment.length > 0
    if (equipmentMissing) evaluation.activeKeys.push('work_equipment_missing')
    if (this.updateCondition('work_equipment_missing', equipmentMissing, now, 1200, 1000, 30000)) {
      const missingNames = missingEquipment.map((label: string) => this.equipmentChineseName(label)).join('、')
      evaluation.alerts.push(new RuleAlert('work_equipment_missing', '关键设备缺失',
        `持续未检测到：${missingNames}`, 'work_equipment_missing.mp3', 1))
    }

    evaluation.primaryStatus = personPresent ? `人员：在岗 ${people.length} 人` : '人员：当前无人'
    evaluation.secondaryStatus = phoneUse ? '手机：疑似使用，请复核' : '手机：未发现使用行为'
    if (!this.equipmentCalibrated) {
      const secondsLeft = Math.max(0, Math.ceil((12000 - (now - this.equipmentCalibrationStartedAt)) / 1000))
      evaluation.detailStatus = `设备：自动学习基线 ${secondsLeft} 秒`
    } else if (this.expectedEquipment.length === 0) {
      evaluation.detailStatus = '设备：基线中未发现关键设备'
    } else if (missingEquipment.length > 0) {
      const names = missingEquipment.map((label: string) => this.equipmentChineseName(label)).join('、')
      evaluation.detailStatus = `设备：缺失 ${names}`
    } else {
      const names = this.expectedEquipment.map((label: string) => this.equipmentChineseName(label)).join('、')
      evaluation.detailStatus = `设备：${names} 正常`
    }
    return evaluation
  }

  private labelSummary(detections: RuleDetection[]): string {
    const names: string[] = []
    for (let index = 0; index < detections.length; index++) this.addUnique(names, detections[index].label)
    return names.join('、')
  }

  private evaluateSecurity(detections: RuleDetection[], now: number): RuleEvaluation {
    const evaluation = new RuleEvaluation()
    const sharp = this.filterByLabel(detections, SHARP_LABELS, 0.25)
    const foodDrink = this.filterByLabel(detections, FOOD_DRINK_LABELS, 0.28)
    const baggage = this.filterByLabel(detections, BAGGAGE_LABELS, 0.28)

    if (sharp.length > 0) {
      evaluation.activeKeys.push('security_sharp')
      for (let index = 0; index < sharp.length; index++) this.addUnique(evaluation.highlightLabels, sharp[index].label)
    }
    if (this.updateCondition('security_sharp', sharp.length > 0, now, 700, 900, 12000)) {
      evaluation.alerts.push(new RuleAlert('security_sharp', '疑似危险物品',
        `检测到 ${this.labelSummary(sharp)}，请立即人工复核`, 'security_sharp.mp3', 2))
    }

    if (foodDrink.length > 0) {
      evaluation.activeKeys.push('security_food_drink')
      for (let index = 0; index < foodDrink.length; index++) {
        this.addUnique(evaluation.highlightLabels, foodDrink[index].label)
      }
    }
    if (this.updateCondition('security_food_drink', foodDrink.length > 0, now, 1000, 1000, 30000)) {
      evaluation.alerts.push(new RuleAlert('security_food_drink', '食品饮品复核',
        `检测到 ${this.labelSummary(foodDrink)}，请进行人工复核`, 'security_food_drink.mp3', 1))
    }

    if (baggage.length > 0) {
      evaluation.activeKeys.push('security_baggage')
      for (let index = 0; index < baggage.length; index++) {
        this.addUnique(evaluation.highlightLabels, baggage[index].label)
      }
    }
    if (this.updateCondition('security_baggage', baggage.length > 0, now, 1000, 1000, 20000)) {
      evaluation.alerts.push(new RuleAlert('security_baggage', '包裹行李复核',
        `检测到 ${this.labelSummary(baggage)}，请进行人工复核`, 'security_baggage.mp3', 1))
    }

    evaluation.primaryStatus = sharp.length > 0 ? `危险物：${this.labelSummary(sharp)}` : '危险物：未发现刀具剪刀'
    evaluation.secondaryStatus = foodDrink.length > 0 ?
      `食品饮品：${foodDrink.length} 件待复核` : '食品饮品：未发现'
    evaluation.detailStatus = baggage.length > 0 ?
      `包裹行李：${baggage.length} 件待复核` : '包裹行李：未发现'
    return evaluation
  }

  private isNearAnyPerson(baggage: RuleDetection, people: RuleDetection[]): boolean {
    const bagX = baggage.centerX()
    const bagY = baggage.centerY()
    for (let index = 0; index < people.length; index++) {
      const person = people[index]
      const expandedX = Math.max(0.08, person.width * 0.35)
      const expandedY = Math.max(0.08, person.height * 0.18)
      if (bagX >= person.x - expandedX && bagX <= person.x + person.width + expandedX &&
        bagY >= person.y - expandedY && bagY <= person.y + person.height + expandedY) return true
    }
    return false
  }

  private distance(x1: number, y1: number, x2: number, y2: number): number {
    const dx = x1 - x2
    const dy = y1 - y2
    return Math.sqrt(dx * dx + dy * dy)
  }

  private updateBaggageTracks(baggage: RuleDetection[], people: RuleDetection[], now: number): BaggageTrack[] {
    const matchedTrackIds: number[] = []
    for (let detectionIndex = 0; detectionIndex < baggage.length; detectionIndex++) {
      const detection = baggage[detectionIndex]
      let bestTrack: BaggageTrack | undefined = undefined
      let bestDistance = 0.14
      for (let trackIndex = 0; trackIndex < this.baggageTracks.length; trackIndex++) {
        const track = this.baggageTracks[trackIndex]
        if (track.label !== detection.label || matchedTrackIds.indexOf(track.id) >= 0) continue
        const currentDistance = this.distance(track.centerX(), track.centerY(), detection.centerX(), detection.centerY())
        if (currentDistance < bestDistance) {
          bestDistance = currentDistance
          bestTrack = track
        }
      }

      const nearPerson = this.isNearAnyPerson(detection, people)
      if (bestTrack === undefined) {
        bestTrack = new BaggageTrack(this.nextTrackId, detection, now, nearPerson)
        this.nextTrackId += 1
        this.baggageTracks.push(bestTrack)
      } else {
        const movedDistance = this.distance(bestTrack.anchorX, bestTrack.anchorY,
          detection.centerX(), detection.centerY())
        if (movedDistance > 0.08) {
          bestTrack.anchorX = detection.centerX()
          bestTrack.anchorY = detection.centerY()
          bestTrack.firstStationaryAt = now
          bestTrack.alerted = false
        }
        bestTrack.x = detection.x
        bestTrack.y = detection.y
        bestTrack.width = detection.width
        bestTrack.height = detection.height
        bestTrack.lastSeenAt = now
      }
      if (nearPerson) {
        bestTrack.lastNearPersonAt = now
        bestTrack.firstStationaryAt = now
        bestTrack.alerted = false
      }
      matchedTrackIds.push(bestTrack.id)
    }

    const remaining: BaggageTrack[] = []
    for (let index = 0; index < this.baggageTracks.length; index++) {
      const track = this.baggageTracks[index]
      if (now - track.lastSeenAt <= 2500) remaining.push(track)
    }
    this.baggageTracks = remaining
    return this.baggageTracks
  }

  private evaluatePublic(detections: RuleDetection[], now: number): RuleEvaluation {
    const evaluation = new RuleEvaluation()
    const people = this.filterByLabel(detections, ['person'], 0.30)
    const baggage = this.filterByLabel(detections, BAGGAGE_LABELS, 0.26)
    const animals = this.filterByLabel(detections, ANIMAL_LABELS, 0.30)
    const tracks = this.updateBaggageTracks(baggage, people, now)

    const crowding = people.length > 3
    if (crowding) {
      evaluation.activeKeys.push('public_crowd')
      this.addUnique(evaluation.highlightLabels, 'person')
    }
    if (this.updateCondition('public_crowd', crowding, now, 2500, 1000, 20000)) {
      evaluation.alerts.push(new RuleAlert('public_crowd', '人员聚集',
        `公共区域检测到 ${people.length} 人，请注意现场秩序`, 'public_crowd.mp3', 1))
    }

    if (animals.length > 0) {
      evaluation.activeKeys.push('public_animal')
      for (let index = 0; index < animals.length; index++) this.addUnique(evaluation.highlightLabels, animals[index].label)
    }
    if (this.updateCondition('public_animal', animals.length > 0, now, 1200, 1000, 30000)) {
      evaluation.alerts.push(new RuleAlert('public_animal', '动物进入公共区域',
        `检测到 ${this.labelSummary(animals)}，请及时处理`, 'public_animal.mp3', 1))
    }

    let unattendedCount = 0
    for (let index = 0; index < tracks.length; index++) {
      const track = tracks[index]
      const unattended = now - track.firstStationaryAt >= 15000 && now - track.lastNearPersonAt >= 10000
      if (!unattended) continue
      unattendedCount += 1
      this.addUnique(evaluation.highlightLabels, track.label)
      if (!track.alerted) {
        track.alerted = true
        evaluation.alerts.push(new RuleAlert(`public_unattended_${track.id}`, '疑似遗留物',
          `${track.label} 已静置且附近持续无人，请立即确认`, 'public_unattended.mp3', 2))
      }
    }
    if (unattendedCount > 0) evaluation.activeKeys.push('public_unattended')

    evaluation.primaryStatus = `人员：${people.length} 人${crowding ? '，疑似聚集' : ''}`
    evaluation.secondaryStatus = `包裹行李：跟踪 ${tracks.length} 件`
    if (unattendedCount > 0) {
      evaluation.detailStatus = `遗留物：${unattendedCount} 件待确认`
    } else if (animals.length > 0) {
      evaluation.detailStatus = `公共秩序：发现 ${this.labelSummary(animals)}`
    } else {
      evaluation.detailStatus = '公共秩序：当前正常'
    }
    return evaluation
  }
}
