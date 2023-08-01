import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'camera_view.dart';
import 'pose_painter.dart';

late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  cameras = await availableCameras();
  runApp(const CameraApp());
}

/// CameraApp is the Main Application.
class CameraApp extends StatefulWidget {
  /// Default Constructor
  const CameraApp({Key? key}) : super(key: key);

  @override
  State<CameraApp> createState() => _CameraAppState();
}

class _CameraAppState extends State<CameraApp> {
  @override
  void initState() {
    super.initState();
  }

  CustomPaint? _customPaint;
  final poseDetector = PoseDetector(options: PoseDetectorOptions());

  Future<void> processImage(InputImage inputImage) async {
    final poses = await poseDetector.processImage(inputImage);
    // for (Pose pose in poses) {
    //   // to access all landmarks
    //   // pose.landmarks.forEach((_, landmark) {
    //   //   final type = landmark.type;
    //   //   final x = landmark.x;
    //   //   final y = landmark.y;
    //   //   // print('type: $type, x: $x, y: $y');
    //   // });

    //   // to access specific landmarks
    // }
    _customPaint = CustomPaint(
        painter: PosePainter(
            poses, inputImage.metadata!.size, inputImage.metadata!.rotation));
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: CameraView(
        title: 'Something',
        customPaint: _customPaint,
        onImage: (inputImage) {
          processImage(inputImage);
        },
      ),
    );
  }
}
