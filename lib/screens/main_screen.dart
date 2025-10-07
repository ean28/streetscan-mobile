import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:street_scan/screens/assessmodel_screen.dart';

import 'home_screen.dart';
import 'camera_screen.dart';
import 'detection_screen.dart';

class MainScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const MainScreen({super.key, required this.cameras});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _selectedIndex == 0
          ? HomeScreen(
              cameras: widget.cameras,
            )
          : Container(), // other screens are pushed, not in tabs
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        fixedColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Colors.grey,
        onTap: (index) {
          if (index == 0) {
            setState(() => _selectedIndex = 0); // Home
          } else if (index == 1) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CameraScreen(cameras: widget.cameras),
              ),
            );
          } else if (index == 2) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DetectionScreen(cameras: widget.cameras),
              ),
            );
          } else if (index == 3){
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AssessModelScreen(),
              ),
            );
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.videocam), label: "Video"),
          BottomNavigationBarItem(icon: Icon(Icons.photo_camera), label: "Detect"),
          BottomNavigationBarItem(icon: Icon(Icons.handyman), label: "Assess Model"),
        ],
      ),
    );
  }
}
