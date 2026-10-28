import { router, promptAction, window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { session, SessionUi } from '../core/Session';
import { BotItem, ChatMessage, Computer, ThreadItem } from '../model/Models';
import { Theme } from '../common/Theme';

class MainScreenUi implements SessionUi {
  private page: MainScreen | null = null;

  bind(page: MainScreen): void {
    this.page = page;
  }

  detach(): void {
    this.page = null;
  }

  onBots(bots: BotItem[]): void {
    const page = this.page;
    if (page !== null) {
      page.applyBots(bots);
    }
  }

  onMessages(threadId: string, messages: ChatMessage[]): void {
    const page = this.page;
    if (page !== null) {
      page.applyMessages(threadId, messages);
    }
  }

  onConnectionState(state: string): void {
    const page = this.page;
    if (page !== null) {
      page.connection = state;
    }
  }

  onServerName(name: string): void {
    const page = this.page;
    if (page !== null) {
      page.serverName = name;
    }
  }
}

@Entry
@Component
struct MainScreen {
  @State bots: BotItem[] = [];
  @State messages: ChatMessage[] = [];
  @State serverName: string = '';
  @State connection: string = 'offline';
  @State openBot: BotItem | null = null;
  @State pickingBot: BotItem | null = null;
  @State openThreadTitle: string = '';
  @State openThreadId: string = '';
  @State detailOpen: boolean = false;
  @State draft: string = '';
  @State sending: boolean = false;
  @State switcherOpen: boolean = false;
  @State computers: Computer[] = [];
  @State answerDraft: string = '';
  @State secretDraft: string = '';
  @State secretBusy: boolean = false;
  @State topInset: number = 36;
  @State bottomInset: number = 16;
  private ui: MainScreenUi = new MainScreenUi();
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.readInsets();
    this.ui.bind(this);
    session.attachUi(this.ui);
    this.computers = session.computers;
    if (!session.hasComputers()) {
      router.replaceUrl({ url: 'pages/PairingScreen' });
      return;
    }
    if (session.current === null) {
      const first = session.computers[0];
      const context = getContext(this) as common.UIAbilityContext;
      session.load(context).then(() => {
        this.computers = session.computers;
        const target = session.current !== null ? session.current : session.computers[0];
        if (target !== undefined) {
          session.useComputer(target);
        }
      }).catch(() => {
        router.replaceUrl({ url: 'pages/PairingScreen' });
      });
    }
  }

  aboutToDisappear(): void {
    this.ui.detach();
    session.detachUi();
  }

  onPageHide(): void {
    this.ui.detach();
    session.detachUi();
  }

  onPageShow(): void {
    this.ui.bind(this);
    session.attachUi(this.ui);
  }

  applyBots(bots: BotItem[]): void {
    this.bots = bots;
    if (this.openBot !== null) {
      let fresh: BotItem | null = null;
      for (const bot of bots) {
        if (bot.id === this.openBot.id) {
          fresh = bot;
          break;
        }
      }
      this.openBot = fresh;
    }
  }

  applyMessages(threadId: string, messages: ChatMessage[]): void {
    if (this.openBot !== null && this.openBot.threadId === threadId) {
      const visible: ChatMessage[] = [];
      for (const message of messages) {
        if (message.kind === 'digest' || message.text.startsWith('[digest]')) {
          continue;
        }
        visible.push(message);
      }
      this.messages = visible;
      this.scrollToEnd();
    }
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Column() {
        this.topBar()
        Divider().color('#e5decd')
        if (this.openBot !== null) {
          this.chatBody()
        } else if (this.pickingBot !== null) {
          this.threadList()
        } else {
          this.botList()
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.topInset, bottom: this.bottomInset })

      if (this.switcherOpen) {
        this.computerSheet()
      }
      if (this.detailOpen) {
        this.threadDetailSheet()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BG)
  }

  @Builder
  topBar() {
    Row({ space: 10 }) {
      if (this.openBot !== null || this.pickingBot !== null) {
        Text('‹')
          .fontSize(24)
          .fontColor(Theme.PRIMARY)
          .onClick(() => {
            this.goBack();
          })
      }
      Row({ space: 8 }) {
        Circle({ width: 9, height: 9 })
          .fill(this.connection === 'online' ? Theme.ONLINE
            : this.connection === 'reconnecting' || this.connection === 'connecting' ? Theme.WARN
              : Theme.INK_FAINT)
        Column({ space: 1 }) {
          Text(this.headerTitle())
            .fontSize(17)
            .fontFamily(Theme.UI_FONT)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.INK)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.headerSubtitle())
            .fontSize(11)
            .fontColor(Theme.INK_FAINT)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .alignItems(VerticalAlign.Center)
      .layoutWeight(1)
      .onClick(() => {
        if (this.openBot === null && this.pickingBot === null) {
          this.computers = session.computers;
          this.switcherOpen = true;
        }
      })

      if (this.openBot !== null) {
        Text('···')
          .fontSize(22)
          .fontFamily(Theme.UI_FONT)
          .fontColor(Theme.INK)
          .padding({ left: 8, right: 4 })
          .onClick(() => {
            this.detailOpen = true;
          })
      }
      Text('断开')
        .fontSize(14)
        .fontFamily(Theme.UI_FONT)
        .fontColor(Theme.DANGER)
        .padding({ left: 8, right: 4 })
        .onClick(() => {
          this.disconnectCurrent();
        })
      if (this.openBot === null) {
        Text('＋')
          .fontSize(22)
          .fontColor(Theme.PRIMARY)
          .onClick(() => {
            router.pushUrl({ url: 'pages/PairingScreen' });
          })
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 10 })
  }

  @Builder
  botList() {
    if (this.bots.length === 0) {
      Column({ space: 10 }) {
        LoadingProgress().width(28).height(28).color(Theme.PRIMARY)
        Text(this.connection === 'online' ? '这台电脑上还没有队友' : '正在连接电脑…')
          .fontSize(13)
          .fontColor(Theme.INK_SOFT)
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else {
      List({ space: 0 }) {
        ForEach(this.bots, (bot: BotItem) => {
          ListItem() {
            Row({ space: 12 }) {
              Stack({ alignContent: Alignment.TopEnd }) {
                Text(this.avatarText(bot.name))
                  .fontSize(16)
                  .fontColor(Color.White)
                  .textAlign(TextAlign.Center)
                  .width(44)
                  .height(44)
                  .borderRadius(22)
                  .backgroundColor(Theme.PRIMARY)
                if (bot.unread) {
                  Circle({ width: 10, height: 10 })
                    .fill('#d14836')
                    .margin({ top: 2, right: 2 })
                }
              }
              Column({ space: 3 }) {
                Row({ space: 8 }) {
                  Text(bot.name)
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Theme.INK)
                    .maxLines(1)
                  if (bot.busy) {
                    Text('工作中')
                      .fontSize(10)
                      .fontColor(Theme.WARN)
                      .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                      .borderRadius(6)
                      .backgroundColor('#f4ead1')
                  }
                }
                Text(bot.tasks.length > 1 ? `${bot.tasks.length} 段对话` : (bot.preview.length > 0 ? bot.preview : '还没有消息'))
                  .fontSize(12)
                  .fontColor(Theme.INK_SOFT)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Column({ space: 2 }) {
                Text(this.timeOf(bot.previewAt))
                  .fontSize(11)
                  .fontColor(Theme.INK_FAINT)
              }
              .alignItems(HorizontalAlign.End)
            }
            .width('100%')
            .padding({ top: 10, bottom: 10, left: 14, right: 14 })
            .onClick(() => {
              this.pickingBot = bot;
            })
          }
        }, (bot: BotItem) => `${bot.id}_${bot.unread}_${bot.busy}_${bot.preview}`)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .divider({ strokeWidth: 1, color: '#eee7d8', startMargin: 70, endMargin: 14 })
    }
  }

  @Builder
  threadList() {
    Column() {
      if (this.pickingBot !== null && this.pickingBot.tasks.length === 0) {
        Text('还没有对话')
          .fontSize(13)
          .fontColor(Theme.INK_SOFT)
          .margin(16)
      }
      List({ space: 0 }) {
        if (this.pickingBot !== null) {
          ForEach(this.pickingBot.tasks, (task: ThreadItem) => {
            ListItem() {
              Column({ space: 4 }) {
                Text(task.title)
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Theme.INK)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text('只包含这一段对话')
                  .fontSize(12)
                  .fontColor(Theme.INK_SOFT)
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding({ left: 16, right: 16, top: 14, bottom: 14 })
              .onClick(() => {
                this.openPicked(task);
              })
            }
          }, (task: ThreadItem) => `${task.threadId}_${task.title}`)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      Button('新对话')
        .width('92%')
        .margin({ bottom: 12 })
        .backgroundColor(Theme.PRIMARY)
        .fontSize(15)
        .onClick(() => {
          this.startThread();
        })
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  chatBody() {
    Column() {
      Scroll(this.scroller) {
        Column({ space: 10 }) {
          ForEach(this.messages, (message: ChatMessage) => {
            this.messageRow(message)
          }, (message: ChatMessage) => `${message.id}_${message.kind}_${message.text.length}_${message.toolOk}_${message.requestPending}`)
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 12, bottom: 8 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      this.executionBar()
      this.composer()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  messageRow(message: ChatMessage) {
    Column({ space: 6 }) {
      if (message.card.kind !== 'none') {
        this.cardView(message)
      } else if (message.toolName.length > 0) {
        this.activityRow(message)
      } else if (message.role === 'user') {
        this.bubble(message)
      } else {
        this.assistantText(message)
      }
    }
    .width('100%')
    .alignItems(message.role === 'user' ? HorizontalAlign.End : HorizontalAlign.Start)
    .onAppear(() => {
      this.scrollToEnd();
    })
  }

  @Builder
  bubble(message: ChatMessage) {
    Column({ space: 0 }) {
      ForEach(this.renderLines(message.text), (line: RenderLine, index: number) => {
        if (line.code) {
          Text(line.text)
            .fontSize(12)
            .fontFamily('monospace')
            .lineHeight(18)
            .fontColor('#28413d')
            .width('100%')
            .padding(8)
            .borderRadius(8)
            .backgroundColor('#efe9da')
            .margin({ top: 4, bottom: 4 })
        } else if (line.heading) {
          Text(line.text)
            .fontSize(13)
            .fontFamily(Theme.UI_FONT)
            .lineHeight(20)
            .fontWeight(FontWeight.Medium)
            .fontColor(message.role === 'user' ? Color.White : Theme.INK)
            .margin({ top: 8 })
        } else if (line.bullet) {
          Row({ space: 6 }) {
            Text('·')
              .fontSize(12)
              .fontFamily(Theme.UI_FONT)
              .fontColor(message.role === 'user' ? Color.White : Theme.PRIMARY)
            Text(line.text)
              .fontSize(12)
              .fontFamily(Theme.UI_FONT)
              .lineHeight(18)
              .fontColor(message.role === 'user' ? Color.White : Theme.INK)
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        } else {
          Text(line.text.length > 0 ? line.text : ' ')
            .fontSize(12)
            .fontFamily(Theme.UI_FONT)
            .lineHeight(18)
            .fontColor(message.role === 'user' ? Color.White : Theme.INK)
        }
      }, (line: RenderLine, index: number) => `${index}_${line.text}`)
    }
    .constraintSize({ maxWidth: '78%' })
    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
    .borderRadius(Theme.RADIUS)
    .backgroundColor(Theme.BUBBLE_USER)
  }

  @Builder
  assistantText(message: ChatMessage) {
    Column({ space: 2 }) {
      ForEach(this.renderLines(this.plainText(message.text)), (line: RenderLine, index: number) => {
        if (line.table) {
          this.tableBlock(line.text)
        } else if (line.code) {
          Text(line.text)
            .fontSize(12)
            .fontFamily('monospace')
            .lineHeight(18)
            .fontColor('#28413d')
            .width('100%')
            .padding(8)
            .borderRadius(8)
            .backgroundColor('#efe9da')
            .margin({ top: 4, bottom: 4 })
        } else if (line.heading) {
          Text(line.text)
            .fontSize(13)
            .fontFamily(Theme.UI_FONT)
            .lineHeight(20)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.INK)
            .width('100%')
            .margin({ top: 10 })
        } else if (line.bullet) {
          Row({ space: 6 }) {
            Text('·')
              .fontSize(12)
              .fontFamily(Theme.UI_FONT)
              .fontColor(Theme.PRIMARY)
            Text(line.text)
              .fontSize(12)
              .fontFamily(Theme.UI_FONT)
              .lineHeight(18)
              .fontColor(Theme.INK)
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        } else {
          Text(line.text.length > 0 ? line.text : ' ')
            .fontSize(12)
            .fontFamily(Theme.UI_FONT)
            .lineHeight(18)
            .fontColor(Theme.INK)
            .width('100%')
        }
      }, (line: RenderLine, index: number) => `ai_${index}_${line.text}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 4, bottom: 8 })
  }

  @Builder
  tableBlock(encoded: string) {
    Scroll() {
      Column() {
        ForEach(encoded.split('\n'), (row: string, rowIndex: number) => {
          Row() {
            ForEach(row.split('\t'), (cell: string, colIndex: number) => {
              Text(cell.length > 0 ? cell : ' ')
                .fontSize(12)
                .fontFamily(Theme.UI_FONT)
                .fontColor(Theme.INK)
                .fontWeight(rowIndex === 0 ? FontWeight.Medium : FontWeight.Normal)
                .lineHeight(18)
                .layoutWeight(1)
                .padding({ left: 10, right: 10, top: 10, bottom: 10 })
            }, (cell: string, colIndex: number) => `${rowIndex}_${colIndex}_${cell}`)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
          .backgroundColor(rowIndex === 0 ? '#efe6d6' : (rowIndex % 2 === 0 ? '#fbf8f0' : Color.White))
          .border({ width: { bottom: 1 }, color: '#e5decd' })
        }, (row: string, rowIndex: number) => `table_${rowIndex}_${row}`)
      }
      .constraintSize({ minWidth: '100%' })
      .border({ width: 1, color: '#e5decd' })
      .borderRadius(10)
      .clip(true)
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .margin({ top: 8, bottom: 8 })
  }

  @Builder
  activityRow(message: ChatMessage) {
    Row({ space: 6 }) {
      LoadingProgress()
        .width(12)
        .height(12)
        .color(Theme.PRIMARY)
        .visibility(message.toolOk ? Visibility.Visible : Visibility.None)
      Text('⚙')
        .fontSize(12)
        .fontColor(message.toolOk ? Theme.PRIMARY : Theme.DANGER)
      Text(this.activityText(message))
        .fontSize(12)
        .fontColor(Theme.INK_SOFT)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ left: 6, right: 6 })
  }

  @Builder
  cardView(message: ChatMessage) {
    Column({ space: 8 }) {
      if (message.card.kind === 'signin') {
        this.signInCard(message)
      } else if (message.card.kind === 'secret') {
        this.secretCard(message)
      } else {
        this.optionsCard(message)
      }
    }
    .width('100%')
  }

  @Builder
  optionsCard(message: ChatMessage) {
    Column({ space: 8 }) {
      Text(message.card.title.length > 0 ? message.card.title : '队友在等你决定')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.INK)
      if (message.card.subtitle.length > 0) {
        Text(message.card.subtitle)
          .fontSize(13)
          .fontColor(Theme.INK_SOFT)
          .lineHeight(19)
      }
      if (message.card.settled) {
        this.cardReceipt(message)
      } else {
        if (message.card.expired) {
          Text('这张卡片已过期，需要队友重新发起。')
            .fontSize(12)
            .fontColor(Theme.INK_FAINT)
        } else {
          ForEach(message.card.options, (option: string, index: number) => {
            Button(option)
              .width('100%')
              .backgroundColor(Theme.PRIMARY_LIGHT)
              .fontColor(Theme.PRIMARY)
              .fontSize(14)
              .onClick(() => {
                this.answerOption(message, option);
              })
          }, (option: string, index: number) => `${index}_${option}`)
          if (!message.card.fixedOptions && message.card.requestId.length > 0) {
            Row({ space: 8 }) {
              TextInput({ text: this.answerDraft, placeholder: '或输入一句话回答' })
                .fontSize(13)
                .backgroundColor('#f2ecdf')
                .layoutWeight(1)
                .onChange((value: string) => {
                  this.answerDraft = value;
                })
              Button('回答')
                .backgroundColor(Theme.PRIMARY)
                .fontSize(13)
                .onClick(() => {
                  this.answerFreeText(message);
                })
            }
            .width('100%')
          }
          if (message.card.requestType === 'permission' && message.card.allowKey.length > 0) {
            Text('始终允许')
              .fontSize(12)
              .fontColor(Theme.PRIMARY)
              .padding({ top: 2, bottom: 2 })
              .onClick(() => {
                this.grantAlways(message);
              })
          }
        }
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius(Theme.RADIUS)
    .backgroundColor(Color.White)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  signInCard(message: ChatMessage) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text('登录请求')
          .fontSize(11)
          .fontColor(Color.White)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .borderRadius(8)
          .backgroundColor(Theme.PRIMARY)
        Text(message.card.signInSite)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.INK)
          .layoutWeight(1)
          .maxLines(1)
      }
      .width('100%')
      if (message.card.signInReason.length > 0) {
        Text(message.card.signInReason)
          .fontSize(13)
          .fontColor(Theme.INK_SOFT)
          .lineHeight(19)
      }
      if (message.card.signInDone || message.card.signInCancelled) {
        Text(message.card.signInDone ? '已完成登录，队友会继续。' : '已取消这次登录请求。')
          .fontSize(12)
          .fontColor(Theme.INK_FAINT)
      } else {
        Text('请先在电脑上打开该网站并登录，登录状态由电脑保存；完成后点「已登录」。')
          .fontSize(12)
          .fontColor(Theme.INK_SOFT)
          .lineHeight(18)
        Row({ space: 10 }) {
          Button('取消')
            .layoutWeight(1)
            .backgroundColor('#e8e1d0')
            .fontColor(Theme.INK_SOFT)
            .fontSize(14)
            .onClick(() => {
              this.settleSignIn(message, false);
            })
          Button('已登录')
            .layoutWeight(1)
            .backgroundColor(Theme.PRIMARY)
            .fontSize(14)
            .onClick(() => {
              this.settleSignIn(message, true);
            })
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius(Theme.RADIUS)
    .backgroundColor(Color.White)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  secretCard(message: ChatMessage) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text('凭证请求')
          .fontSize(11)
          .fontColor(Color.White)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .borderRadius(8)
          .backgroundColor(Theme.WARN)
        Text(message.card.secretLabel.length > 0 ? message.card.secretLabel : '一项密钥')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.INK)
          .layoutWeight(1)
          .maxLines(1)
      }
      .width('100%')
      if (message.card.secretDescription.length > 0) {
        Text(message.card.secretDescription)
          .fontSize(13)
          .fontColor(Theme.INK_SOFT)
          .lineHeight(19)
      }
      if (message.card.secretProvided) {
        Text('已在电脑上保存。')
          .fontSize(12)
          .fontColor(Theme.INK_FAINT)
      } else if (message.card.secretDismissed) {
        Text('已忽略这张凭证请求。')
          .fontSize(12)
          .fontColor(Theme.INK_FAINT)
      } else {
        Text('内容会加密后交给电脑，手机和网络上看不到明文。')
          .fontSize(12)
          .fontColor(Theme.INK_FAINT)
        TextInput({ text: this.secretDraft, placeholder: '在这里输入要保存的内容' })
          .type(InputType.Password)
          .width('100%')
          .enabled(!this.secretBusy)
          .onChange((value: string) => {
            this.secretDraft = value;
          })
        Row({ space: 10 }) {
          Button('忽略')
            .layoutWeight(1)
            .backgroundColor('#e8e1d0')
            .fontColor(Theme.INK_SOFT)
            .fontSize(14)
            .enabled(!this.secretBusy)
            .onClick(() => {
              this.dismissSecret(message);
            })
          Button(this.secretBusy ? '正在保存' : '保存到电脑')
            .layoutWeight(1)
            .backgroundColor(Theme.PRIMARY)
            .fontSize(14)
            .enabled(!this.secretBusy)
            .onClick(() => {
              this.submitSecret(message);
            })
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius(Theme.RADIUS)
    .backgroundColor(Color.White)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  cardReceipt(message: ChatMessage) {
    Column({ space: 4 }) {
      if (message.card.answered.length > 0) {
        Row({ space: 6 }) {
          Text('已回答')
            .fontSize(11)
            .fontColor(Theme.ONLINE)
          Text(message.card.answered)
            .fontSize(13)
            .fontColor(Theme.INK)
        }
      }
      if (message.card.answeredText.length > 0) {
        Text(message.card.answeredText)
          .fontSize(13)
          .fontColor(Theme.INK_SOFT)
      }
      if (message.card.dismissed) {
        Text('已忽略这张卡片。')
          .fontSize(12)
          .fontColor(Theme.INK_FAINT)
      }
      if (message.card.expired) {
        Text('这张卡片已过期。')
          .fontSize(12)
          .fontColor(Theme.INK_FAINT)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  executionBar() {
    if (this.openBot !== null && this.openBot.busy) {
      Row({ space: 10 }) {
        LoadingProgress().width(16).height(16).color(Theme.PRIMARY)
        Column({ space: 2 }) {
          Text(`${this.openBot.name} 正在处理`)
            .fontSize(13)
            .fontColor(Theme.PRIMARY)
            .fontWeight(FontWeight.Medium)
          Text(this.executionDetail())
            .fontSize(11)
            .fontColor(Theme.INK_SOFT)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Button('停止')
          .backgroundColor('#e8e1d0')
          .fontColor(Theme.DANGER)
          .fontSize(12)
          .height(30)
          .onClick(() => {
            session.interrupt();
          })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .backgroundColor(Theme.PRIMARY_LIGHT)
    }
  }

  @Builder
  composer() {
    Row({ space: 8 }) {
      TextInput({ text: this.draft, placeholder: this.openBot !== null ? `发给 ${this.openBot.name}` : '输入消息' })
        .fontSize(13)
        .fontFamily(Theme.UI_FONT)
        .backgroundColor('#f2ecdf')
        .layoutWeight(1)
        .onChange((value: string) => {
          this.draft = value;
        })
        .onSubmit(() => {
          this.sendDraft();
        })
      if (this.sending) {
        LoadingProgress().width(22).height(22).color(Theme.PRIMARY)
      } else {
        Button('发送')
          .backgroundColor(Theme.PRIMARY)
          .fontSize(14)
          .onClick(() => {
            this.sendDraft();
          })
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 8, bottom: 12 })
    .backgroundColor('#fbf8f0')
  }

  @Builder
  threadDetailSheet() {
    Column() {
      Column({ space: 12 }) {
        Row() {
          Text('这段对话')
            .fontSize(17)
            .fontFamily(Theme.UI_FONT)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.INK)
            .layoutWeight(1)
          Text('关闭')
            .fontSize(14)
            .fontFamily(Theme.UI_FONT)
            .fontColor(Theme.PRIMARY)
            .onClick(() => {
              this.detailOpen = false;
            })
        }
        .width('100%')
        this.detailRow('名称', this.openThreadTitle.length > 0 ? this.openThreadTitle : '未命名对话')
        this.detailRow('队友', this.openBot !== null ? this.openBot.name : '')
        this.detailRow('电脑', this.serverName.length > 0 ? this.serverName : '这台电脑')
        this.detailRow('模型', this.currentModel().length > 0 ? this.currentModel() : '跟随队友')
        this.detailRow('连接', this.connectionLabel())
        this.detailRow('编号', this.openThreadId)
      }
      .width('100%')
      .padding(16)
      .backgroundColor(Color.White)
      .borderRadius({ topLeft: Theme.RADIUS, topRight: Theme.RADIUS })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(22,51,47,0.35)')
    .justifyContent(FlexAlign.End)
    .onClick(() => {
      this.detailOpen = false;
    })
  }

  @Builder
  detailRow(label: string, value: string) {
    Column({ space: 2 }) {
      Text(label)
        .fontSize(11)
        .fontFamily(Theme.UI_FONT)
        .fontColor(Theme.INK_FAINT)
      Text(value.length > 0 ? value : '—')
        .fontSize(14)
        .fontFamily(Theme.UI_FONT)
        .fontColor(Theme.INK)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  computerSheet() {
    Column() {
      Column({ space: 10 }) {
        Row({ space: 8 }) {
          Text('已保存的电脑')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.INK)
            .layoutWeight(1)
          Text('关闭')
            .fontSize(14)
            .fontColor(Theme.PRIMARY)
            .onClick(() => {
              this.switcherOpen = false;
            })
        }
        .width('100%')
        ForEach(this.computers, (computer: Computer) => {
          Row({ space: 10 }) {
            Text(this.avatarText(computer.serverName))
              .fontSize(14)
              .fontColor(Color.White)
              .textAlign(TextAlign.Center)
              .width(36)
              .height(36)
              .borderRadius(18)
              .backgroundColor(session.current !== null && session.current.id === computer.id ? Theme.PRIMARY : Theme.INK_FAINT)
            Column({ space: 2 }) {
              Text(computer.serverName)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.INK)
              Text(computer.baseUrl)
                .fontSize(11)
                .fontColor(Theme.INK_FAINT)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            if (session.current !== null && session.current.id === computer.id) {
              Text('当前')
                .fontSize(11)
                .fontColor(Theme.PRIMARY)
                .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                .borderRadius(8)
                .backgroundColor(Theme.PRIMARY_LIGHT)
            } else {
              Text('切换')
                .fontSize(13)
                .fontColor(Theme.PRIMARY)
                .padding(4)
                .onClick(() => {
                  this.switchComputer(computer);
                })
            }
            Text('断开')
              .fontSize(12)
              .fontColor(Theme.INK_FAINT)
              .padding(4)
              .onClick(() => {
                this.removeComputer(computer);
              })
          }
          .width('100%')
          .padding({ top: 6, bottom: 6 })
        }, (computer: Computer) => `${computer.id}_${computer.baseUrl}_${computer.serverName}`)
        Button('添加另一台电脑')
          .width('100%')
          .backgroundColor(Theme.PRIMARY_LIGHT)
          .fontColor(Theme.PRIMARY)
          .fontSize(14)
          .margin({ top: 4 })
          .onClick(() => {
            this.switcherOpen = false;
            router.pushUrl({ url: 'pages/PairingScreen' });
          })
        Text('切换只更换当前连接，其他电脑的配对会保留在本机。')
          .fontSize(11)
          .fontColor(Theme.INK_FAINT)
      }
      .width('100%')
      .padding(16)
      .backgroundColor(Color.White)
      .borderRadius({ topLeft: Theme.RADIUS, topRight: Theme.RADIUS })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(22,51,47,0.35)')
    .justifyContent(FlexAlign.End)
    .onClick(() => {
      this.switcherOpen = false;
    })
  }

  private readInsets(): void {
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

  private connectionLabel(): string {
    if (this.connection === 'online') {
      return '已连接';
    }
    if (this.connection === 'reconnecting' || this.connection === 'connecting') {
      return '正在同步';
    }
    if (this.connection === 'idle') {
      return '未连接';
    }
    return '未连接';
  }

  private avatarText(name: string): string {
    if (name.length === 0) {
      return '电';
    }
    return name.slice(0, 1);
  }

  private timeOf(at: number): string {
    if (at <= 0) {
      return '';
    }
    const date = new Date(at);
    const hours = date.getHours();
    const minutes = date.getMinutes();
    const hourText = hours < 10 ? `0${hours}` : `${hours}`;
    const minuteText = minutes < 10 ? `0${minutes}` : `${minutes}`;
    return `${hourText}:${minuteText}`;
  }

  private activityText(message: ChatMessage): string {
    const summary = message.toolSummary.length > 0 ? message.toolSummary : message.text;
    const okText = message.toolOk ? '' : '（失败）';
    return `${message.toolName}${okText}${summary.length > 0 ? ` · ${summary}` : ''}`;
  }

  private executionDetail(): string {
    for (let i = this.messages.length - 1; i >= 0; i--) {
      const message = this.messages[i];
      if (message.toolName.length > 0) {
        return this.activityText(message);
      }
    }
    return '收到新消息时会在这里同步进度';
  }

  private plainText(text: string): string {
    return text.replace(/\*\*/g, '').replace(/__/g, '');
  }

  private currentModel(): string {
    const bot = this.openBot;
    if (bot === null) {
      return '';
    }
    for (const task of bot.tasks) {
      if (task.threadId === this.openThreadId && task.model.length > 0) {
        return task.model;
      }
    }
    return '';
  }

  private isTableRule(line: string): boolean {
    const cells = this.splitCells(line);
    if (cells.length < 2) {
      return false;
    }
    for (const cell of cells) {
      if (!/^:?-{3,}:?$/.test(cell)) {
        return false;
      }
    }
    return true;
  }

  private isTableRow(line: string): boolean {
    const trimmed = line.trim();
    return trimmed.indexOf('|') >= 0 && this.splitCells(trimmed).length >= 2;
  }

  private splitCells(line: string): string[] {
    let raw = line.trim();
    if (raw.startsWith('|')) {
      raw = raw.slice(1);
    }
    if (raw.endsWith('|')) {
      raw = raw.slice(0, raw.length - 1);
    }
    const parts = raw.split('|');
    const cells: string[] = [];
    for (const part of parts) {
      cells.push(this.plainText(part.trim()));
    }
    return cells;
  }

  private pushTable(lines: RenderLine[], rawRows: string[]): void {
    const rows: string[] = [];
    for (const raw of rawRows) {
      if (this.isTableRule(raw)) {
        continue;
      }
      rows.push(this.splitCells(raw).join('\t'));
    }
    if (rows.length === 0) {
      return;
    }
    const line = new RenderLine(rows.join('\n'), false, false, false);
    line.table = true;
    lines.push(line);
  }

  private renderLines(text: string): RenderLine[] {
    const lines: RenderLine[] = [];
    const source = text.length > 0 ? text : '';
    const parts = source.split('\n');
    let inCode = false;
    let codeBuffer: string[] = [];
    let tableBuffer: string[] = [];
    const flushTable = (): void => {
      if (tableBuffer.length > 0) {
        this.pushTable(lines, tableBuffer);
        tableBuffer = [];
      }
    };
    for (const part of parts) {
      const trimmed = part.trim();
      if (trimmed.startsWith('```')) {
        flushTable();
        if (inCode) {
          lines.push(new RenderLine(codeBuffer.join('\n'), true, false, false));
          codeBuffer = [];
          inCode = false;
        } else {
          inCode = true;
        }
        continue;
      }
      if (inCode) {
        codeBuffer.push(part);
        continue;
      }
      if (trimmed.length === 0) {
        flushTable();
        continue;
      }
      if (this.isTableRow(trimmed)) {
        tableBuffer.push(trimmed);
        continue;
      }
      flushTable();
      if (trimmed.startsWith('#')) {
        lines.push(new RenderLine(this.plainText(trimmed.replace(/^#+\s*/, '')), false, true, false));
      } else if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        lines.push(new RenderLine(this.plainText(trimmed.slice(2)), false, false, true));
      } else {
        lines.push(new RenderLine(this.plainText(part), false, false, false));
      }
    }
    flushTable();
    if (codeBuffer.length > 0) {
      lines.push(new RenderLine(codeBuffer.join('\n'), true, false, false));
    }
    return lines;
  }

  private scrollToEnd(): void {
    try {
      this.scroller.scrollEdge(Edge.Bottom);
    } catch (_error) {
    }
  }

  private headerTitle(): string {
    if (this.openBot !== null) {
      return this.openBot.name;
    }
    if (this.pickingBot !== null) {
      return this.pickingBot.name;
    }
    return '联伴';
  }

  private headerSubtitle(): string {
    const status = this.connection === 'online' ? '已同步' : this.connectionLabel();
    if (this.openBot !== null) {
      const title = this.openThreadTitle;
      if (title.length > 0 && title !== this.openBot.name && title !== '当前对话' && title !== '新对话') {
        return `${title} · ${status}`;
      }
      return status;
    }
    if (this.pickingBot !== null) {
      return '选择一段对话';
    }
    const computer = this.serverName.length > 0 && this.serverName !== '联伴' ? this.serverName : '';
    return computer.length > 0 ? `${computer} · 点这里切换电脑` : '点这里切换电脑';
  }

  private goBack(): void {
    if (this.openBot !== null) {
      session.closeBot();
      this.openBot = null;
      this.messages = [];
      this.answerDraft = '';
      this.openThreadTitle = '';
      this.openThreadId = '';
      this.detailOpen = false;
      return;
    }
    this.pickingBot = null;
  }

  private openPicked(task: ThreadItem): void {
    const bot = this.pickingBot;
    if (bot === null) {
      return;
    }
    this.openConversation(bot, task);
  }

  private async startThread(): Promise<void> {
    const bot = this.pickingBot;
    if (bot === null) {
      return;
    }
    try {
      const created = await session.createThread(bot);
      let fresh = bot;
      for (const item of this.bots) {
        if (item.id === bot.id) {
          fresh = item;
          break;
        }
      }
      this.pickingBot = fresh;
      await this.openConversation(fresh, created);
    } catch (error) {
      const text = error instanceof Error ? error.message : '没能新建对话';
      promptAction.showToast({ message: text, duration: 2500 });
    }
  }

  private async openConversation(bot: BotItem, task: ThreadItem): Promise<void> {
    this.openThreadTitle = task.title;
    this.openThreadId = task.threadId;
    this.detailOpen = false;
    this.openBot = bot;
    this.messages = [];
    this.answerDraft = '';
    await session.openThread(bot, task.threadId);
    this.messages = session.messagesOf(task.threadId);
    this.scrollToEnd();
  }

  private async sendDraft(): Promise<void> {
    const text = this.draft.trim();
    if (text.length === 0 || this.sending) {
      return;
    }
    this.sending = true;
    try {
      await session.send(text);
      this.draft = '';
      this.scrollToEnd();
    } catch (error) {
      const message = error instanceof Error ? error.message : '发送失败';
      promptAction.showToast({ message: message, duration: 2500 });
    } finally {
      this.sending = false;
    }
  }

  private async answerOption(message: ChatMessage, option: string): Promise<void> {
    if (message.card.kind === 'none') {
      return;
    }
    const card = message.card;
    if (card.requestId.length > 0) {
      const behavior = card.requestType === 'permission' && (option === '允许' || option === 'Allow') ? 'allow'
        : card.requestType === 'permission' && (option === '拒绝' || option === 'Deny') ? 'deny' : 'answer';
      try {
        await session.respondCard(card.requestId, behavior, behavior === 'answer' ? option : '');
      } catch (error) {
        const text = error instanceof Error ? error.message : '操作失败';
        promptAction.showToast({ message: text, duration: 2500 });
      }
    } else {
      promptAction.showToast({ message: '这张卡片已不能回答', duration: 2000 });
    }
  }

  private async answerFreeText(message: ChatMessage): Promise<void> {
    if (message.card.kind === 'none' || this.answerDraft.trim().length === 0) {
      return;
    }
    const requestId = message.card.requestId;
    const answer = this.answerDraft.trim();
    try {
      await session.respondCard(requestId, 'answer', answer);
      this.answerDraft = '';
    } catch (error) {
      const text = error instanceof Error ? error.message : '回答失败';
      promptAction.showToast({ message: text, duration: 2500 });
    }
  }

  private async grantAlways(message: ChatMessage): Promise<void> {
    if (message.card.kind === 'none' || message.card.allowKey.length === 0) {
      return;
    }
    try {
      await session.alwaysAllowCard(message.card.allowKey);
    } catch (error) {
      const text = error instanceof Error ? error.message : '设置失败';
      promptAction.showToast({ message: text, duration: 2500 });
    }
  }

  private async dismissSecret(message: ChatMessage): Promise<void> {
    this.secretBusy = true;
    try {
      await session.dismissSecret(message.id);
      this.secretDraft = '';
    } catch (error) {
      const text = error instanceof Error ? error.message : '忽略失败';
      promptAction.showToast({ message: text, duration: 2500 });
    }
    this.secretBusy = false;
  }

  private async submitSecret(message: ChatMessage): Promise<void> {
    if (message.card.secretTarget.length === 0 || message.card.secretRequestKey.length === 0) {
      promptAction.showToast({ message: '这张凭证卡片缺少提交信息，请在电脑上输入。', duration: 2500 });
      return;
    }
    this.secretBusy = true;
    try {
      await session.provideSecret(message.id, message.card.secretTarget, message.card.secretRequestKey, this.secretDraft);
      this.secretDraft = '';
      promptAction.showToast({ message: '已加密保存到电脑', duration: 2000 });
    } catch (error) {
      const text = error instanceof Error ? error.message : '保存失败';
      promptAction.showToast({ message: text, duration: 3000 });
    }
    this.secretBusy = false;
  }

  private async settleSignIn(message: ChatMessage, done: boolean): Promise<void> {
    try {
      await session.signInCard(message.id, done);
    } catch (error) {
      const text = error instanceof Error ? error.message : '操作失败';
      promptAction.showToast({ message: text, duration: 2500 });
    }
  }

  private async switchComputer(computer: Computer): Promise<void> {
    this.switcherOpen = false;
    this.pickingBot = null;
    this.openBot = null;
    this.openThreadTitle = '';
    this.messages = [];
    promptAction.showToast({ message: `正在连接 ${computer.serverName}…`, duration: 1500 });
    try {
      await session.useComputer(computer);
    } catch (error) {
      const text = error instanceof Error ? error.message : '连接失败';
      promptAction.showToast({ message: text, duration: 2500 });
    }
  }

  private async disconnectCurrent(): Promise<void> {
    const current = session.current;
    if (current === null) {
      session.disconnect();
      router.replaceUrl({ url: 'pages/PairingScreen' });
      return;
    }
    await this.removeComputer(current);
  }

  private async removeComputer(computer: Computer): Promise<void> {
    await session.removeComputer(computer.id);
    this.computers = session.computers;
    if (!session.hasComputers()) {
      this.switcherOpen = false;
      router.replaceUrl({ url: 'pages/PairingScreen' });
      return;
    }
    if (session.current === null) {
      this.switcherOpen = false;
      const next = session.computers[0];
      await session.useComputer(next);
    }
  }
}

class RenderLine {
  text: string = '';
  code: boolean = false;
  heading: boolean = false;
  bullet: boolean = false;
  table: boolean = false;

  constructor(text: string, code: boolean, heading: boolean, bullet: boolean) {
    this.text = text;
    this.code = code;
    this.heading = heading;
    this.bullet = bullet;
  }
}
