import { router } from '@kit.ArkUI';

@Entry
@Component
struct Splash {
  build() {
    Stack() {
      // 灰色背景（视频不够大时露出）
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#151419')

      // 视频播放器（全屏，无控件）
      Video({
        src: $rawfile('first.mp4'),
        controller: new VideoController()
      })
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .autoPlay(true)
        .loop(false)
        .muted(true)
        .controls(false)
        .backgroundColor('#151419')
        .onFinish(() => {
          router.replaceUrl({ url: 'pages/Index' });
        })
        .onError(() => {
          router.replaceUrl({ url: 'pages/Index' });
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#151419')
  }
}
