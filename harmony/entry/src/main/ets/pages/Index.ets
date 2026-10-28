import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { session } from '../core/Session';
import { Theme } from '../common/Theme';

@Entry
@Component
struct Index {
  aboutToAppear(): void {
    const context = getContext(this) as common.UIAbilityContext;
    session.load(context).then(() => {
      if (session.hasComputers()) {
        router.replaceUrl({ url: 'pages/MainScreen' });
      } else {
        router.replaceUrl({ url: 'pages/PairingScreen' });
      }
    }).catch(() => {
      router.replaceUrl({ url: 'pages/PairingScreen' });
    });
  }

  build() {
    Column({ space: 14 }) {
      LoadingProgress()
        .width(34)
        .height(34)
        .color(Theme.PRIMARY)
      Text('联伴')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.PRIMARY)
      Text('正在准备…')
        .fontSize(12)
        .fontColor(Theme.INK_SOFT)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BG)
    .justifyContent(FlexAlign.Center)
  }
}
