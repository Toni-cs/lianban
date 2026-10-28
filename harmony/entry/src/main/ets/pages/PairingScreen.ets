import { router, window } from '@kit.ArkUI';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { common } from '@kit.AbilityKit';
import { LianbanClient } from '../api/LianbanClient';
import { session } from '../core/Session';
import { MdnsFinder, NearbyComputer } from '../core/MdnsFinder';
import { Theme } from '../common/Theme';
import {
  PairingInvite, parsePairingLink, transportKindOf, transportLabelOf, transportNoteOf
} from '../model/Models';

@Entry
@Component
struct PairingScreen {
  @State view: string = 'welcome';
  @State linkDraft: string = '';
  @State manualAddress: string = '';
  @State manualCode: string = '';
  @State manualName: string = '';
  @State nearby: NearbyComputer[] = [];
  @State pairing: boolean = false;
  @State pairError: string = '';
  @State confirmName: string = '';
  @State confirmKind: string = 'lan';
  @State confirmBaseUrl: string = '';
  @State confirmCredential: string = '';
  @State confirmSecretKey: string = '';
  @State topInset: number = 36;
  @State bottomInset: number = 16;
  private finder: MdnsFinder = new MdnsFinder();

  aboutToAppear(): void {
    const context = getContext(this) as common.UIAbilityContext;
    window.getLastWindow(context).then((win: window.Window) => {
      const status = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const gesture = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      let top = px2vp(status.topRect.height);
      let bottom = px2vp(gesture.bottomRect.height);
      if (top < 24) {
        top = 36;
      }
      if (bottom < 8) {
        bottom = 16;
      }
      this.topInset = top;
      this.bottomInset = bottom;
    }).catch(() => {
      this.topInset = 36;
      this.bottomInset = 16;
    });
  }

  aboutToDisappear(): void {
    this.finder.stop();
  }

  build() {
    Column() {
      this.header()
      Scroll() {
        Column({ space: 14 }) {
          if (this.view === 'welcome') {
            this.welcomeBody()
          } else if (this.view === 'nearby') {
            this.nearbyBody()
          } else if (this.view === 'manual') {
            this.manualBody()
          } else if (this.view === 'confirm') {
            this.confirmBody()
          }
        }
        .width('100%')
        .padding(16)
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.topInset, bottom: this.bottomInset })
    .backgroundColor(Theme.BG)
  }

  @Builder
  header() {
    Row({ space: 10 }) {
      if (this.view !== 'welcome' && this.view !== 'confirm') {
        Text('‹')
          .fontSize(24)
          .fontColor(Theme.PRIMARY)
          .onClick(() => {
            this.view = 'welcome';
          })
      }
      Column({ space: 2 }) {
        Text('联伴')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.PRIMARY)
        Text('连接你的电脑')
          .fontSize(12)
          .fontColor(Theme.INK_SOFT)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 18, left: 16, right: 16, bottom: 6 })
  }

  @Builder
  welcomeBody() {
    Column({ space: 14 }) {
      Column({ space: 10 }) {
        Text('扫码配对')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.INK)
        Text('在电脑上打开「设置 → 远程访问」，选择「配对手机」，然后用下方入口扫描屏幕上的二维码。')
          .fontSize(13)
          .fontColor(Theme.INK_SOFT)
          .lineHeight(20)
        Button('扫描二维码')
          .width('100%')
          .backgroundColor(Theme.PRIMARY)
          .fontSize(15)
          .onClick(() => {
            this.startScan();
          })
        Divider().color('#e5decd')
        Text('扫不了码？把二维码对应的配对链接粘贴到这里（以 openmausbot://pair 开头）。')
          .fontSize(12)
          .fontColor(Theme.INK_FAINT)
        TextInput({ text: this.linkDraft, placeholder: 'openmausbot://pair?address=…' })
          .fontSize(13)
          .backgroundColor('#f2ecdf')
          .onChange((value: string) => {
            this.linkDraft = value;
          })
        Button('解析并连接')
          .width('100%')
          .backgroundColor(Theme.PRIMARY_LIGHT)
          .fontColor(Theme.PRIMARY)
          .fontSize(14)
          .onClick(() => {
            this.useLink();
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(16)
      .borderRadius(Theme.RADIUS)
      .backgroundColor(Color.White)

      Column({ space: 6 }) {
        Text('其他连接方式')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.INK)
        Text('二维码不可用时，可以找到附近的电脑，或手动输入电脑上显示的地址和六位配对码。')
          .fontSize(12)
          .fontColor(Theme.INK_SOFT)
          .lineHeight(18)
        Row({ space: 10 }) {
          Column({ space: 2 }) {
            Text('附近的电脑')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.INK)
            Text('同一 Wi-Fi 下自动发现已开启远程访问的电脑')
              .fontSize(12)
              .fontColor(Theme.INK_FAINT)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Blank()
          Text('›')
            .fontSize(20)
            .fontColor(Theme.INK_FAINT)
        }
        .width('100%')
        .padding({ top: 10, bottom: 4 })
        .onClick(() => {
          this.view = 'nearby';
          this.startNearby();
        })
        Divider().color('#eee7d8')
        Row({ space: 10 }) {
          Column({ space: 2 }) {
            Text('手动输入地址')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.INK)
            Text('输入电脑显示的地址与六位配对码')
              .fontSize(12)
              .fontColor(Theme.INK_FAINT)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Blank()
          Text('›')
            .fontSize(20)
            .fontColor(Theme.INK_FAINT)
        }
        .width('100%')
        .padding({ top: 10, bottom: 4 })
        .onClick(() => {
          this.manualName = '';
          this.view = 'manual';
        })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(16)
      .borderRadius(Theme.RADIUS)
      .backgroundColor(Color.White)

      if (this.pairing) {
        Row({ space: 8 }) {
          LoadingProgress().width(18).height(18).color(Theme.PRIMARY)
          Text('正在配对…')
            .fontSize(13)
            .fontColor(Theme.PRIMARY)
        }
      }
      if (this.pairError.length > 0) {
        Text(this.pairError)
          .fontSize(13)
          .fontColor(Theme.DANGER)
          .width('100%')
          .padding(12)
          .borderRadius(Theme.RADIUS_SMALL)
          .backgroundColor('#f6e3de')
      }
    }
    .width('100%')
  }

  @Builder
  nearbyBody() {
    Column({ space: 12 }) {
      Column({ space: 8 }) {
        Text('附近的电脑')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.INK)
        Text('正在同一网络里寻找开启了远程访问的电脑…仅在你信任的网络上使用。')
          .fontSize(12)
          .fontColor(Theme.INK_SOFT)
        if (this.nearby.length === 0) {
          Row({ space: 8 }) {
            LoadingProgress().width(16).height(16).color(Theme.INK_FAINT)
            Text('还没有发现电脑，稍等几秒后可重新查找。')
              .fontSize(12)
              .fontColor(Theme.INK_FAINT)
          }
          .padding({ top: 6, bottom: 4 })
        }
        ForEach(this.nearby, (computer: NearbyComputer) => {
          Row({ space: 10 }) {
            Text(this.avatarText(computer.display()))
              .fontSize(15)
              .fontColor(Color.White)
              .textAlign(TextAlign.Center)
              .width(38)
              .height(38)
              .borderRadius(19)
              .backgroundColor(Theme.PRIMARY)
            Column({ space: 2 }) {
              Text(computer.display())
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.INK)
              Text(computer.target())
                .fontSize(12)
                .fontColor(Theme.INK_FAINT)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Blank()
            Text('选择')
              .fontSize(13)
              .fontColor(Theme.PRIMARY)
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })
          .onClick(() => {
            this.manualAddress = computer.target();
            this.manualName = computer.display();
            this.view = 'manual';
          })
        }, (computer: NearbyComputer) => computer.instance)
        Button('重新查找')
          .width('100%')
          .backgroundColor(Theme.PRIMARY_LIGHT)
          .fontColor(Theme.PRIMARY)
          .fontSize(14)
          .margin({ top: 6 })
          .onClick(() => {
            this.startNearby();
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(16)
      .borderRadius(Theme.RADIUS)
      .backgroundColor(Color.White)
    }
    .width('100%')
  }

  @Builder
  manualBody() {
    Column({ space: 12 }) {
      Column({ space: 10 }) {
        Text(this.manualName.length > 0 ? `连接 ${this.manualName}` : '手动连接电脑')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.INK)
        Text('在电脑「设置 → 远程访问 → 安全的 HTTPS 配对」里点「配对设备」。把那里直接显示的六位数字填在下面，不要填带字母的配对码。')
          .fontSize(12)
          .fontColor(Theme.INK_SOFT)
          .lineHeight(18)
        TextInput({ text: this.manualAddress, placeholder: '例如 192.168.1.10:8810' })
          .fontSize(13)
          .backgroundColor('#f2ecdf')
          .onChange((value: string) => {
            this.manualAddress = value;
          })
        TextInput({ text: this.manualCode, placeholder: '六位配对码' })
          .fontSize(13)
          .type(InputType.Number)
          .backgroundColor('#f2ecdf')
          .onChange((value: string) => {
            this.manualCode = value;
          })
        Button('连接这台电脑')
          .width('100%')
          .backgroundColor(Theme.PRIMARY)
          .fontSize(15)
          .onClick(() => {
            this.pairManual();
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(16)
      .borderRadius(Theme.RADIUS)
      .backgroundColor(Color.White)
      if (this.pairing) {
        Row({ space: 8 }) {
          LoadingProgress().width(18).height(18).color(Theme.PRIMARY)
          Text('正在配对…')
            .fontSize(13)
            .fontColor(Theme.PRIMARY)
        }
      }
      if (this.pairError.length > 0) {
        Text(this.pairError)
          .fontSize(13)
          .fontColor(Theme.DANGER)
          .width('100%')
          .padding(12)
          .borderRadius(Theme.RADIUS_SMALL)
          .backgroundColor('#f6e3de')
      }
    }
    .width('100%')
  }

  @Builder
  confirmBody() {
    Column({ space: 12 }) {
      Column({ space: 12 }) {
        Text('确认配对')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.INK)
        Row({ space: 12 }) {
          Text(this.avatarText(this.confirmName))
            .fontSize(18)
            .fontColor(Color.White)
            .textAlign(TextAlign.Center)
            .width(48)
            .height(48)
            .borderRadius(24)
            .backgroundColor(Theme.PRIMARY)
          Column({ space: 3 }) {
            Text(this.confirmName.length > 0 ? this.confirmName : '未命名电脑')
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.INK)
            Text(transportLabelOf(this.confirmKind))
              .fontSize(12)
              .fontColor(Theme.PRIMARY)
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              .borderRadius(8)
              .backgroundColor(Theme.PRIMARY_LIGHT)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        Text(transportNoteOf(this.confirmKind))
          .fontSize(13)
          .fontColor(Theme.INK_SOFT)
          .lineHeight(19)
        Text(this.confirmBaseUrl)
          .fontSize(12)
          .fontColor(Theme.INK_FAINT)
        Divider().color('#e5decd')
        Text('确认后，这台手机会获得该电脑上对话的访问权。电脑随时可以在「远程访问」里撤销。')
          .fontSize(12)
          .fontColor(Theme.INK_SOFT)
          .lineHeight(18)
        Row({ space: 10 }) {
          Button('返回')
            .layoutWeight(1)
            .backgroundColor('#e8e1d0')
            .fontColor(Theme.INK_SOFT)
            .fontSize(15)
            .onClick(() => {
              this.view = 'welcome';
              this.pairError = '';
            })
          Button('信任并连接')
            .layoutWeight(2)
            .backgroundColor(Theme.PRIMARY)
            .fontSize(15)
            .onClick(() => {
              this.runPairing();
            })
        }
        .width('100%')
        if (this.pairing) {
          Row({ space: 8 }) {
            LoadingProgress().width(18).height(18).color(Theme.PRIMARY)
            Text('正在配对…')
              .fontSize(13)
              .fontColor(Theme.PRIMARY)
          }
        }
        if (this.pairError.length > 0) {
          Text(this.pairError)
            .fontSize(13)
            .fontColor(Theme.DANGER)
            .width('100%')
            .padding(10)
            .borderRadius(Theme.RADIUS_SMALL)
            .backgroundColor('#f6e3de')
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(16)
      .borderRadius(Theme.RADIUS)
      .backgroundColor(Color.White)
    }
    .width('100%')
  }

  private avatarText(name: string): string {
    if (name.length === 0) {
      return '电';
    }
    return name.slice(0, 1);
  }

  private startScan(): void {
    const options: scanBarcode.ScanOptions = {
      scanTypes: [scanCore.ScanType.QR_CODE],
      enableMultiMode: false,
      enableAlbum: true
    };
    const context = getContext(this) as common.UIAbilityContext;
    scanBarcode.startScanForResult(context, options).then((result: scanBarcode.ScanResult) => {
      const value = result.originalValue;
      if (typeof value === 'string' && value.length > 0) {
        this.applyLink(value);
      }
    }).catch(() => {
      this.pairError = '无法打开扫码，请把配对链接粘贴到输入框里。';
    });
  }

  private useLink(): void {
    if (this.linkDraft.trim().length === 0) {
      this.pairError = '请先粘贴配对链接。';
      return;
    }
    this.applyLink(this.linkDraft);
  }

  private applyLink(link: string): void {
    const invite: PairingInvite = parsePairingLink(link);
    if (!invite.ok) {
      this.pairError = invite.error.length > 0 ? invite.error : '配对链接无法识别';
      return;
    }
    this.pairError = '';
    this.confirmName = invite.name;
    this.confirmKind = invite.kind;
    this.confirmBaseUrl = invite.baseUrl();
    this.confirmCredential = invite.token.length > 0 ? invite.token : invite.code;
    this.confirmSecretKey = invite.secretKey;
    this.view = 'confirm';
  }

  private startNearby(): void {
    this.nearby = [];
    this.finder.start((computers: NearbyComputer[]) => {
      this.nearby = computers.filter((computer: NearbyComputer) => computer.address.length > 0);
    });
  }

  private pairManual(): void {
    const address = this.manualAddress.trim();
    const code = this.manualCode.trim();
    if (address.length === 0) {
      this.pairError = '请输入电脑显示的地址。';
      return;
    }
    if (!/^\d{6}$/.test(code)) {
      this.pairError = '六位配对码是六个数字，在电脑的「远程访问」里查看。';
      return;
    }
    this.pairError = '';
    this.confirmName = this.manualName;
    this.confirmKind = transportKindOf(normalizeBaseUrl(address));
    this.confirmBaseUrl = normalizeBaseUrl(address);
    this.confirmCredential = code;
    this.confirmSecretKey = '';
    this.runPairing();
  }

  private async runPairing(): Promise<void> {
    if (this.pairing) {
      return;
    }
    this.pairing = true;
    this.pairError = '';
    const client = new LianbanClient(this.confirmBaseUrl);
    try {
      const outcome = await client.pair(this.confirmCredential);
      if (!outcome.ok) {
        this.pairError = outcome.error.length > 0 ? outcome.error : '配对失败，请重试。';
        this.pairing = false;
        return;
      }
      const computer = await session.addPairedComputer(
        this.confirmBaseUrl, outcome.token, outcome.serverName, this.confirmKind, outcome.endpoints,
        outcome.deviceId, this.confirmSecretKey);
      this.pairing = false;
      await session.useComputer(computer);
      router.replaceUrl({ url: 'pages/MainScreen' });
    } catch (error) {
      this.pairing = false;
      this.pairError = error instanceof Error ? error.message : '配对失败，请检查地址和网络。';
    }
  }
}

function normalizeBaseUrl(input: string): string {
  const trimmed = input.trim();
  if (/^https?:\/\//i.test(trimmed)) {
    return trimmed.replace(/\/+$/, '');
  }
  const withPort = trimmed.includes(':') ? trimmed : `${trimmed}:8810`;
  return `http://${withPort}`;
}
