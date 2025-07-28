import 'package:flutter/material.dart';
import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:get/get_state_manager/src/rx_flutter/rx_obx_widget.dart';
import 'package:get/get_state_manager/src/simple/get_state.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_room/widgets/button.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  RtcEngine? engine;
  bool localUserJoined = false;
  int? remoteUid;
  String token =
      '007eJxTYLCtX9HxVem5juFtfwvmFKPPYutm1YV/mBgmk1F6Yc9iqQYFBnNDSwuLNCMTwzQTSxMDi1RLi2SDJLM0y8Rkk+S01BTztZvaMxoCGRns7PSYGBkgEMRnZfBIzcnJZ2AAACevHrs=';
  String channelName = 'Hello';
  bool engineInitialized = false;

  // Track connected users to enforce 2-user limit
  Set<int> connectedUsers = <int>{};
  bool channelFull = false;

  Future<void> _initializeAgoraVoiceSDK() async {
    await _requestPermissions();

    engine = createAgoraRtcEngine();
    await engine!.initialize(
      const RtcEngineContext(
        appId: "71988f241f49408e98c0b6f9ac4cfed7",
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ),
    );

    // Enable video and configure video settings
    await engine!.enableVideo();
    await engine!.enableLocalVideo(true);
    await engine!.enableAudio();

    // Set video encoder configuration for better quality
    await engine!.setVideoEncoderConfiguration(
      const VideoEncoderConfiguration(
        dimensions: VideoDimensions(width: 640, height: 480),
        frameRate: 15,
        bitrate: 0, // Use default bitrate
        orientationMode: OrientationMode.orientationModeAdaptive,
      ),
    );

    await engine!.startPreview();
    _setupEventHandlers();
    engineInitialized = true;
  }

  Future<void> _requestPermissions() async {
    await [Permission.microphone, Permission.camera].request();
  }

  // Join a channel
  Future<void> joinChannel() async {
    if (!engineInitialized) {
      await _initializeAgoraVoiceSDK();
    }

    await engine!.joinChannel(
      token: token,
      channelId: channelName,
      options: const ChannelMediaOptions(
        autoSubscribeVideo: true,
        autoSubscribeAudio: true,
        publishCameraTrack: true,
        publishMicrophoneTrack: true,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
      ),
      uid: 0,
    );
  }

  // Leave channel
  Future<void> leaveChannel() async {
    await engine?.leaveChannel();
    setState(() {
      localUserJoined = false;
      remoteUid = null;
      connectedUsers.clear();
      channelFull = false;
    });
  }

  // Kick extra users (third user onwards)
  Future<void> _kickUser(int uid) async {
    // You can implement server-side logic to kick users
    // For now, we'll just ignore their video/audio
    debugPrint("Channel is full. User $uid should be kicked.");

    // Show a message to the user
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Channel is full. Maximum 2 users allowed."),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  // Register an event handler for Agora RTC
  void _setupEventHandlers() {
    engine!.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          debugPrint("Local user ${connection.localUid} joined");
          setState(() => localUserJoined = true);
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          debugPrint("Remote user $remoteUid joined");

          // Check if channel already has maximum users
          if (connectedUsers.length >= 1) {
            // Channel is full (local + 1 remote = 2 users max)
            debugPrint("Channel is full! Rejecting user $remoteUid");
            _kickUser(remoteUid);
            setState(() => channelFull = true);
            return;
          }

          // Add user if space available
          connectedUsers.add(remoteUid);
          setState(() {
            this.remoteUid = remoteUid;
            channelFull = connectedUsers.length >= 1;
          });
        },
        onUserOffline: (
          RtcConnection connection,
          int uid,
          UserOfflineReasonType reason,
        ) {
          debugPrint("Remote user $uid left");
          connectedUsers.remove(uid);

          setState(() {
            if (this.remoteUid == uid) {
              this.remoteUid = null;
            }
            channelFull = false;
          });
        },
        onRemoteVideoStateChanged: (
          RtcConnection connection,
          int remoteUid,
          RemoteVideoState state,
          RemoteVideoStateReason reason,
          int elapsed,
        ) {
          debugPrint("Remote video state changed: $state, reason: $reason");

          // Only handle video state for allowed users
          if (!connectedUsers.contains(remoteUid)) {
            debugPrint(
              "Ignoring video state change for unauthorized user: $remoteUid",
            );
            return;
          }
        },
        onLocalVideoStateChanged: (
          VideoSourceType source,
          LocalVideoStreamState state,
          LocalVideoStreamReason reason,
        ) {
          debugPrint("Local video state changed: $state, reason: $reason");
        },
        onConnectionStateChanged: (
          RtcConnection connection,
          ConnectionStateType state,
          ConnectionChangedReasonType reason,
        ) {
          debugPrint("Connection state changed: $state, reason: $reason");
        },
      ),
    );
  }

  @override
  void dispose() {
    engine?.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Video Room"),
        backgroundColor: channelFull ? Colors.orange : Colors.transparent,
        actions: [
          if (channelFull)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Center(
                child: Text(
                  "FULL",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              // Connection status
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color:
                      channelFull
                          ? Colors.orange.shade100
                          : Colors.green.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  channelFull
                      ? "Channel Full - 2/2 Users Connected"
                      : "Users Connected: ${connectedUsers.length + (localUserJoined ? 1 : 0)}/2",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color:
                        channelFull
                            ? Colors.orange.shade800
                            : Colors.green.shade800,
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Local video view
              Stack(
                children: [
                  Container(
                    width: double.infinity,
                    height: 250,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.blue),
                    ),
                    child:
                        localUserJoined && engine != null
                            ? AgoraVideoView(
                              controller: VideoViewController(
                                rtcEngine: engine!,
                                canvas: const VideoCanvas(uid: 0),
                              ),
                            )
                            : const Center(child: Text("Not Joined yet")),
                  ),
                  Align(
                    alignment: Alignment.topRight,
                    child: IconButton(
                      icon: const Icon(
                        Icons.cameraswitch,
                        size: 30,
                        color: Colors.white,
                      ),
                      onPressed:
                          localUserJoined
                              ? () async {
                                await engine?.switchCamera();
                              }
                              : null,
                    ),
                  ),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        "You",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Remote video view
              Container(
                width: double.infinity,
                height: 250,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.green),
                ),
                child:
                    remoteUid != null && engine != null
                        ? AgoraVideoView(
                          controller: VideoViewController.remote(
                            rtcEngine: engine!,
                            connection: RtcConnection(channelId: channelName),
                            canvas: VideoCanvas(uid: remoteUid),
                          ),
                        )
                        : Center(
                          child: Text(
                            channelFull
                                ? "Channel Full"
                                : "Waiting for friend...",
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
              ),
              const SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Button(
                    btnName: 'Start Video Call',
                    icon: Icons.video_call,
                    color:
                        localUserJoined ? Colors.grey.shade300 : Colors.green,
                    ontap:
                        localUserJoined
                            ? null
                            : () async {
                              await joinChannel();
                            },
                  ),
                  Button(
                    btnName: 'End Call',
                    icon: Icons.call_end,
                    color: localUserJoined ? Colors.red : Colors.grey.shade300,
                    ontap:
                        !localUserJoined
                            ? null
                            : () async {
                              await leaveChannel();
                            },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
