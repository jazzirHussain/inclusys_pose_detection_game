import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

import '../main.dart';
import 'dart:typed_data';

// enum ScreenMode { liveFeed, gallery }

class CameraView extends StatefulWidget {
  const CameraView(
      {Key? key,
      required this.title,
      required this.onImage,
      required this.customPaint,
      this.initialDirection = CameraLensDirection.back})
      : super(key: key);

  final String title;
  final Function(InputImage inputImage) onImage;
  final CameraLensDirection initialDirection;
  final CustomPaint? customPaint;

  @override
  State<CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<CameraView> {
  // ScreenMode _mode = ScreenMode.liveFeed;
  CameraController? _controller;
  final int _cameraIndex = 0;

  @override
  void initState() {
    super.initState();

    // if (cameras.any(
    //   (element) =>
    //       element.lensDirection == widget.initialDirection &&
    //       element.sensorOrientation == 90,
    // )) {
    //   _cameraIndex = cameras.indexOf(
    //     cameras.firstWhere((element) =>
    //         element.lensDirection == widget.initialDirection &&
    //         element.sensorOrientation == 90),
    //   );
    // } else {
    //   for (var i = 0; i < cameras.length; i++) {
    //     if (cameras[i].lensDirection == widget.initialDirection) {
    //       _cameraIndex = i;
    //       break;
    //     }
    //   }
    // }

    if (_cameraIndex != -1) {
      _startLiveFeed();
    }
  }

  @override
  void dispose() {
    _stopLiveFeed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: _liveFeedBody(),
    );
  }

  Widget _liveFeedBody() {
    if (_controller?.value.isInitialized == false) {
      return Container();
    }

    final size = MediaQuery.of(context).size;
    // calculate scale depending on screen and camera ratios
    // this is actually size.aspectRatio / (1 / camera.aspectRatio)
    // because camera preview size is received as landscape
    // but we're calculating for portrait orientation
    var scale = size.aspectRatio * _controller!.value.aspectRatio;

    // to prevent scaling down, invert the value
    if (scale < 1) scale = 1 / scale;

    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Transform.scale(
            scale: scale,
            child: Center(child: CameraPreview(_controller!)),
          ),
          if (widget.customPaint != null) widget.customPaint!
        ],
      ),
    );
  }

  Future _startLiveFeed() async {
    final camera = cameras[_cameraIndex];
    _controller = CameraController(
      camera,
      // Set to ResolutionPreset.high. Do NOT set it to ResolutionPreset.max because for some phones does NOT work.
      ResolutionPreset.medium,
      enableAudio: false,
      // imageFormatGroup: Platform.isAndroid
      //     ? ImageFormatGroup.nv21
      //     : ImageFormatGroup.bgra8888,
    );
    _controller?.initialize().then((_) {
      if (!mounted) {
        return;
      }
      _controller?.startImageStream(_processCameraImage);
      setState(() {});
    });
  }

  Future _stopLiveFeed() async {
    await _controller?.stopImageStream();
    await _controller?.dispose();
    _controller = null;
  }

  void _processCameraImage(CameraImage image) {
    final inputImage = _inputImageFromCameraImage(image);
    if (inputImage == null) return;
    widget.onImage(inputImage);
  }

  Uint8List? convertYUV420ToNV21(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final int ySize = width * height;
    final int uvSize = ySize ~/ 4;

    final Uint8List nv21 = Uint8List(ySize + uvSize * 2);

    final Uint8List yBuffer = image.planes[0].bytes;
    final Uint8List uBuffer = image.planes[1].bytes;
    final Uint8List vBuffer = image.planes[2].bytes;

    int rowStride = image.planes[0].bytesPerRow;
    assert(image.planes[0].bytesPerPixel == 1);

    int pos = 0;

    if (rowStride == width) {
      nv21.setRange(0, ySize, yBuffer);
      pos += ySize;
    } else {
      int yBufferPos = -rowStride;
      for (; pos < ySize; pos += width) {
        yBufferPos += rowStride;
        nv21.setRange(pos, pos + width, yBuffer, yBufferPos);
      }
    }

    rowStride = image.planes[2].bytesPerRow;
    int? pixelStride = image.planes[2].bytesPerPixel;
    if (pixelStride == null) return null;
    assert(rowStride == image.planes[1].bytesPerRow);
    assert(pixelStride == image.planes[1].bytesPerPixel);

    if (pixelStride == 2 && rowStride == width && uBuffer[0] == vBuffer[1]) {
      // Maybe V and U planes overlap as per NV21, which means vBuffer[1] is an alias of uBuffer[0]
      final int savePixel = vBuffer[1];
      try {
        vBuffer[1] = (~savePixel & 0xFF).toUnsigned(8);
        if (uBuffer[0] == (~savePixel & 0xFF).toUnsigned(8)) {
          vBuffer[1] = savePixel;
          nv21.setRange(ySize, ySize + 1, vBuffer);
          nv21.setRange(ySize + 1, ySize + 1 + uBuffer.length, uBuffer);

          return nv21; // Shortcut
        }
      } catch (ex) {
        // Unfortunately, we cannot check if vBuffer and uBuffer overlap
      }
      vBuffer[1] = savePixel;
    }

    for (int row = 0; row < height ~/ 2; row++) {
      for (int col = 0; col < width ~/ 2; col++) {
        final int vuPos = col * pixelStride + row * rowStride;
        nv21[pos++] = vBuffer[vuPos];
        nv21[pos++] = uBuffer[vuPos];
      }
    }

    return nv21;
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    // get camera rotation
    final camera = cameras[_cameraIndex];
    final rotation =
        InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    if (rotation == null) return null;

    const format = InputImageFormat.nv21;

    Uint8List? img = convertYUV420ToNV21(image);
    if (img == null) return null;
    return InputImage.fromBytes(
      bytes: img,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation, // used only in Android
        format: format, // used only in iOS
        bytesPerRow: image.width, // used only in iOS
      ),
    );
  }
}
