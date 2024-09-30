import { audio } from '@kit.AudioKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { abilityAccessCtrl, Permissions, PermissionRequestResult } from '@kit.AbilityKit';
import { common } from '@kit.AbilityKit';
import { fileIo as fs, ReadOptions } from '@kit.CoreFileKit';
import { promptAction } from '@kit.ArkUI';

@Entry
@Component
struct Index {
  @State message: string = "Audio 实现音频录制及播放功能";
  audioCapturer: audio.AudioCapturer | null = null
  audioRenderer: audio.AudioRenderer | null = null
  destFile: fs.File | null = null
  @State touchType: TouchType = TouchType.Cancel
  @State buttonSize: number = 100
  timer: number = 0
  @State loadingState: boolean = false

  aboutToAppear(): void {
    this.requestPermission()
    this.createAudioRenderer()
  }

  /**
   * 创建音频采集器
   */
  createAudioCapturer() {
    let audioCapturerOptions: audio.AudioCapturerOptions = {
      // 音频流信息
      streamInfo: {
        samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_44100,
        channels: audio.AudioChannel.CHANNEL_2,
        sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
        encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
      },
      // 采集器信息
      capturerInfo: {
        source: audio.SourceType.SOURCE_TYPE_MIC,
        capturerFlags: 0
      }
    }

    audio.createAudioCapturer(audioCapturerOptions, (err, data) => {
      if (err) {
        console.error(`luvi > AudioCapturer Created : Error: ${err}`);
      } else {
        console.info('luvi > AudioCapturer Created : Success.');
        // 音频采集器对象
        this.audioCapturer = data;
      }
    });
  }

  /**
   * 创建音频渲染器
   */
  createAudioRenderer() {
    let audioRendererOptions: audio.AudioRendererOptions = {
      streamInfo: {
        samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_48000, // 采样率
        channels: audio.AudioChannel.CHANNEL_2, // 通道
        sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE, // 采样格式
        encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW // 编码格式
      },
      rendererInfo: {
        content: audio.ContentType.CONTENT_TYPE_MUSIC, // 媒体类型
        usage: audio.StreamUsage.STREAM_USAGE_MEDIA, // 音频流使用类型
        rendererFlags: 0 // 音频渲染器标志
      }
    }
    audio.createAudioRenderer(audioRendererOptions, (err, renderer) => { // 创建AudioRenderer实例
      if (!err) {
        console.info(`luvi > creating AudioRenderer success`);
        this.audioRenderer = renderer;
        this.audioRenderer.on('stateChange', (state) => { // 设置监听事件，当转换到指定的状态时触发回调
          if (state == 2) {
            console.info('luvi > audio renderer state is: STATE_RUNNING');
          }
        });
        this.audioRenderer.on('markReach', 1000, (position) => { // 订阅markReach事件，当渲染的帧数达到1000帧时触发回调
          if (position == 1000) {
            console.info('luvi > ON Triggered successfully');
          }
        });
      } else {
        console.info(`luvi > creating AudioRenderer failed, error: ${err.message}`);
      }
    });
  }

  /**
   * 请求权限
   */
  requestPermission() {
    let permissionList: Permissions[] = ["ohos.permission.MICROPHONE"]
    // 获取访问控制模块对象
    let atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    let context: Context = getContext(this) as common.UIAbilityContext;
    atManager.requestPermissionsFromUser(context, permissionList,
      (err: BusinessError, data: PermissionRequestResult) => {
        if (err) {
          console.error(`luvi > requestPermissionsFromUser fail, err->${JSON.stringify(err)}`);
        } else {
          console.info('luvi > data:' + JSON.stringify(data));
          console.info('luvi > data permissions:' + data.permissions);
          console.info('luvi > data authResults:' + data.authResults);
          console.info('luvi > data dialogShownResults:' + data.dialogShownResults);
          // 麦克风权限获取成功
          // 创建音频采集器
          this.createAudioCapturer()
        }
      });
  }

  /**
   * 采集音频
   */
  startRecording() {
    let path = getContext().getApplicationContext().filesDir;
    let bufferSize: number = 0;
    let filePath = path + '/MyVoice.wav';
    this.destFile =
      fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.READ_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    let readDataCallback = (buffer: ArrayBuffer) => {
      let options: ReadOptions = {
        offset: bufferSize,
        length: buffer.byteLength
      }
      fs.writeSync(this.destFile?.fd, buffer, options);
      bufferSize += buffer.byteLength;
    }
    this.audioCapturer?.on('readData', readDataCallback);

    this.audioCapturer?.start((err: BusinessError) => {
      if (err) {
        console.error('luvi > Capturer start failed.');
      } else {
        console.info('luvi > Capturer start success.');
      }
    });

    this.loadingState = true
  }

  /**
   * 结束录音
   */
  endRecording() {
    this.audioCapturer?.stop((err: BusinessError) => {
      if (err) {
        console.error('luvi > Capturer stop failed');
      } else {
        console.info('luvi > Capturer stopped.');
        fs.close(this.destFile)
      }
    });

    // 结束定时器
    clearInterval(this.timer)
    this.buttonSize = 100
    this.loadingState = false
  }

  /**
   * 播放音频
   */
  async playVoice() {
    if (!this.audioRenderer) {
      return
    }
    let stateGroup = [audio.AudioState.STATE_PREPARED, audio.AudioState.STATE_PAUSED, audio.AudioState.STATE_STOPPED];
    if (stateGroup.indexOf(this.audioRenderer.state) === -1) { // 当且仅当状态为prepared、paused和stopped之一时才能启动渲染
      console.error('luvi > start failed');
      return;
    }
    await this.audioRenderer.start(); // 启动渲染

    const bufferSize = await this.audioRenderer.getBufferSize();
    let context = getContext(this).getApplicationContext();
    let path = context.filesDir;
    const filePath = path + '/MyVoice.wav'; // 使用沙箱路径获取文件，实际路径为/data/storage/el2/base/haps/entry/files/test.wav

    let file = fs.openSync(filePath, fs.OpenMode.READ_ONLY);
    let stat = await fs.stat(filePath);
    let buf = new ArrayBuffer(bufferSize);
    let len =
      stat.size % bufferSize === 0 ? Math.floor(stat.size / bufferSize) : Math.floor(stat.size / bufferSize + 1);
    for (let i = 0; i < len; i++) {
      let options: ReadOptions = {
        offset: i * bufferSize,
        length: bufferSize
      };
      let readsize = await fs.read(file.fd, buf, options);

      // buf是要写入缓冲区的音频数据，在调用AudioRenderer.write()方法前可以进行音频数据的预处理，实现个性化的音频播放功能，AudioRenderer会读出写入缓冲区的音频数据进行渲染
      let writeSize: number = await new Promise((resolve, reject) => {
        this.audioRenderer?.write(buf, (err, writeSize) => {
          if (err) {
            reject(err);
          } else {
            resolve(writeSize);
          }
        });
      });
      if (this.audioRenderer.state === audio.AudioState.STATE_RELEASED) { // 如果渲染器状态为released，停止渲染
        fs.close(file);
        await this.audioRenderer.stop();
      }
      if (this.audioRenderer.state === audio.AudioState.STATE_RUNNING) {
        if (i === len - 1) { // 如果音频文件已经被读取完，停止渲染
          fs.close(file);
          await this.audioRenderer.stop();
        }
      }
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        if (this.touchType == TouchType.Down && this.loadingState) {
          Image($rawfile("load.gif")).width("70%").margin({ top: 200 })
        }

        if (this.touchType == TouchType.Up && !this.loadingState) {
          Row() {
            Text("音频：MyVoice.wav")
              .fontWeight(FontWeight.Bold)

            Image($rawfile("play.png")).width(35).height(35).margin({ left: 100 })
              .onClick(() => {
                promptAction.showToast({ message: "开始播放啦" })
                this.playVoice()
              })
          }
          .margin({ top: 120 })
          .borderRadius(10)
          .border({ width: 3 })
          .padding({
            top: 20,
            bottom: 20,
            left: 18,
            right: 18
          })
        }
      }
      .width("100%")
      .height("100%")


      Column() {
        Text((this.touchType == TouchType.Down && this.touchType !== null) ? "录音中" : "长按\n录音")
          .textAlign(TextAlign.Center)
          .fontColor("#fff")
          .width(90)
          .height(90)
          .backgroundColor("#000")
          .border({ width: 15, color: "#fff" })
          .borderRadius(999)
          .margin({ top: 5 })
          .fontSize(13)
      }
      .alignItems(HorizontalAlign.Center)
      .width(100)
      .height(100)
      .margin({ bottom: 80 })
      .borderRadius(999)
      .animation({ duration: 700 })
      .backgroundColor(this.touchType == TouchType.Up ? "#fff" : "#ff000000")
      .gesture(LongPressGesture({ repeat: false })
        .onAction((event: GestureEvent) => {
          this.touchType = TouchType.Down
          this.startRecording()
          console.log("luvi > startRecording.")
        })// 长按动作一结束触发
        .onActionEnd((event: GestureEvent) => {
          this.touchType = TouchType.Up
          this.endRecording()
          console.log("luvi > endRecording.")
        }))
    }
    .height('100%')
    .width('100%')
  }
}