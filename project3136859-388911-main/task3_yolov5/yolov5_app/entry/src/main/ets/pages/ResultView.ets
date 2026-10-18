import { hilog } from '@kit.PerformanceAnalysisKit';
import http from '@ohos.net.http';
import { router } from '@kit.ArkUI';

const DOMAIN = 0x0000;
const TAG = 'ResultView';

interface ColorTokens {
  bg: string;
  surface: string;
  surface2: string;
  border: string;
  accent: string;
  active: string;
  success: string;
  danger: string;
  text: string;
  dim: string;
  dimmer: string;
}

const C: ColorTokens = {
  bg:       '#080C14',
  surface:  '#0F1520',
  surface2: '#141C2B',
  border:   '#1C2638',
  accent:   '#3B82F6',
  active:   '#22D3EE',
  success:  '#10B981',
  danger:   '#EF4444',
  text:     '#CBD5E1',
  dim:      '#64748B',
  dimmer:   '#334155',
};

interface ResultPair {
  original: string;
  detected: string;
}

@Entry
@Component
struct ResultView {
  @State resultPairs: ResultPair[] = [];
  @State selectedIndex: number = -1;
  @State serverUrl: string = 'http://127.0.0.1:5000';
  @State urlPrefix: string = '/output/';
  @State saveStatus: string = '';
  @State isSaving: boolean = false;

  aboutToAppear(): void {
    this.resultPairs = JSON.parse(AppStorage.get<string>('resultPairs') || '[]') as ResultPair[];
    this.serverUrl = AppStorage.get<string>('serverUrl') || 'http://127.0.0.1:5000';
    this.urlPrefix = AppStorage.get<string>('urlPrefix') || '/output/';
    if (this.resultPairs.length > 0) this.selectedIndex = 0;
  }

  private getUrl(filename: string): string {
    return `${this.serverUrl}${this.urlPrefix}${filename}`;
  }

  private selectItem(index: number): void {
    this.selectedIndex = index;
    this.saveStatus = '';
  }

  private async saveToLongTerm(): Promise<void> {
    if (this.selectedIndex < 0 || this.selectedIndex >= this.resultPairs.length) return;
    this.isSaving = true;
    try {
      const hr = http.createHttp();
      const res = await hr.request(`${this.serverUrl}/save`, {
        method: http.RequestMethod.POST, readTimeout: 10000,
        header: { 'Content-Type': 'application/json' },
        extraData: JSON.stringify({ filename: this.resultPairs[this.selectedIndex].detected })
      });
      hr.destroy();
      const r = JSON.parse(res.result as string) as Record<string, Object>;
      this.saveStatus = r.msg === 'saved' ? 'SAVED' : 'FAILED';
    } catch (e) {
      this.saveStatus = 'FAILED';
      hilog.error(DOMAIN, TAG, 'save: %{public}s', JSON.stringify(e));
    }
    this.isSaving = false;
  }

  build() {
    Column() {
      // ── Header ────────────────────────────────────────
      Row() {
        Button() {
          Text('返回')
            .fontSize(11)
            .fontFamily('monospace')
            .fontWeight(FontWeight.Bold)
            .fontColor(C.text)
            .letterSpacing(1)
        }
        .height(32)
        .padding({ left: 12, right: 12 })
        .backgroundColor(C.surface)
        .border({ width: 1, color: C.border })
        .borderRadius(4)
        .onClick(() => router.back())

        Blank()

        Text(this.urlPrefix === '/output/' ? '识别结果' : '保存记录')
          .fontSize(13)
          .fontFamily('monospace')
          .fontWeight(FontWeight.Bold)
          .fontColor(C.text)
          .letterSpacing(2)

        Blank()

        // Count badge
        Text(`${this.resultPairs.length}`)
          .fontSize(11)
          .fontFamily('monospace')
          .fontWeight(FontWeight.Bold)
          .fontColor(C.active)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .backgroundColor(C.surface)
          .border({ width: 1, color: C.border })
          .borderRadius(4)
      }
      .width('100%')
      .height(52)
      .padding({ left: 12, right: 12 })
      .backgroundColor(C.surface)
      .border({ width: { bottom: 1 }, color: C.border })

      if (this.resultPairs.length === 0) {
        Column() {
          Text('∅')
            .fontSize(40)
            .fontColor(C.dimmer)
          Text(this.urlPrefix === '/output/' ? '暂无识别结果' : '暂无保存记录')
            .fontSize(16)
            .fontColor(C.dim)
            .margin({ top: 8 })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Row() {
          // ── Left: result list ──────────────────────────
          Column() {
            Text('图片列表')
              .fontSize(9)
              .fontFamily('monospace')
              .fontWeight(FontWeight.Bold)
              .fontColor(C.dimmer)
              .letterSpacing(2)
              .padding({ left: 10, top: 10, bottom: 6 })

            List({ space: 3 }) {
              ForEach(this.resultPairs, (pair: ResultPair, index: number) => {
                ListItem() {
                  Row() {
                    Text(`${String(index + 1).padStart(2, '0')}`)
                      .fontSize(10)
                      .fontFamily('monospace')
                      .fontWeight(FontWeight.Bold)
                      .fontColor(index === this.selectedIndex ? C.active : C.dimmer)
                      .width(22)

                    Text(pair.detected)
                      .fontSize(10)
                      .fontFamily('monospace')
                      .fontColor(index === this.selectedIndex ? C.text : C.dim)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)

                    if (index === this.selectedIndex) {
                      Row()
                        .width(3)
                        .height(16)
                        .backgroundColor(C.active)
                        .borderRadius(1)
                    }
                  }
                  .width('100%')
                  .height(36)
                  .padding({ left: 10, right: 8 })
                  .backgroundColor(index === this.selectedIndex ? '#0D1B2A' : 'transparent')
                  .borderRadius(4)
                  .border({
                    width: { left: 2 },
                    color: index === this.selectedIndex ? C.accent : 'transparent'
                  })
                  .onClick(() => this.selectItem(index))
                }
              })
            }
            .layoutWeight(1)
            .width('100%')
            .padding({ left: 2, right: 2 })
          }
          .width('30%')
          .height('100%')
          .backgroundColor(C.surface)
          .border({ width: { right: 1 }, color: C.border })

          // ── Right: image comparison ────────────────────
          Column() {
            if (this.selectedIndex >= 0 && this.selectedIndex < this.resultPairs.length) {
              Scroll() {
                Column() {
                  // Original
                  Column() {
                    Row() {
                      Text('原图')
                        .fontSize(9)
                        .fontFamily('monospace')
                        .fontWeight(FontWeight.Bold)
                        .fontColor(C.dimmer)
                        .letterSpacing(1.5)
                    }
                    .width('100%')
                    .padding({ bottom: 6 })

                    Image(this.getUrl(this.resultPairs[this.selectedIndex].original))
                      .width('100%')
                      .aspectRatio(1.5)
                      .objectFit(ImageFit.Contain)
                      .backgroundColor(C.surface2)
                      .borderRadius(4)
                      .border({ width: 1, color: C.border })
                  }
                  .width('100%')
                  .padding({ left: 10, right: 10, top: 10 })

                  // Detected
                  Column() {
                    Row() {
                      Text('识别结果')
                        .fontSize(9)
                        .fontFamily('monospace')
                        .fontWeight(FontWeight.Bold)
                        .fontColor(C.dimmer)
                        .letterSpacing(1.5)

                      Blank()

                      Text('▲')
                        .fontSize(10)
                        .fontColor(C.active)
                    }
                    .width('100%')
                    .padding({ bottom: 6 })

                    Image(this.getUrl(this.resultPairs[this.selectedIndex].detected))
                      .width('100%')
                      .aspectRatio(1.5)
                      .objectFit(ImageFit.Contain)
                      .backgroundColor(C.surface2)
                      .borderRadius(4)
                      .border({ width: 1, color: C.accent })
                  }
                  .width('100%')
                  .padding({ left: 10, right: 10, top: 14 })

                  // Save section
                  if (this.urlPrefix === '/output/') {
                    Column() {
                      Divider().color(C.border).width('100%').margin({ bottom: 12 })

                      Button() {
                        Row({ space: 6 }) {
                          if (this.isSaving) {
                            LoadingProgress().width(14).height(14).color(C.bg)
                          } else {
                            Text('↓').fontSize(14).fontColor(C.bg)
                          }
                          Text(this.isSaving ? '保存中...' : '保存')
                            .fontSize(13)
                            .fontWeight(FontWeight.Bold)
                            .fontColor(C.bg)
                        }
                      }
                      .width('100%')
                      .height(40)
                      .borderRadius(6)
                      .backgroundColor(this.isSaving ? C.dimmer : C.success)
                      .enabled(!this.isSaving)
                      .onClick(() => this.saveToLongTerm())

                      if (this.saveStatus.length > 0) {
                        Text(this.saveStatus)
                          .fontSize(10)
                          .fontFamily('monospace')
                          .fontWeight(FontWeight.Bold)
                          .fontColor(this.saveStatus === 'SAVED' ? C.success : C.danger)
                          .letterSpacing(1)
                          .margin({ top: 6 })
                      }
                    }
                    .width('100%')
                    .padding({ left: 10, right: 10, top: 14, bottom: 20 })
                  }
                }
              }
              .layoutWeight(1)
              .width('100%')
              .scrollBar(BarState.Auto)
            } else {
              Column() {
                Text('←')
                  .fontSize(28)
                  .fontColor(C.dimmer)
                Text('请选择图片')
                  .fontSize(11)
                  .fontFamily('monospace')
                  .fontColor(C.dim)
                  .letterSpacing(1.5)
                  .margin({ top: 6 })
              }
              .layoutWeight(1)
              .justifyContent(FlexAlign.Center)
            }
          }
          .width('70%')
          .height('100%')
        }
        .layoutWeight(1)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(C.bg)
  }
}
