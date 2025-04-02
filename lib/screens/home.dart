import 'package:flutter/material.dart';
import 'package:time_buddies/screens/home_page.dart';
import 'package:time_buddies/screens/calendar_screen.dart';
import 'package:time_buddies/screens/collaboration_screen.dart';
import 'package:time_buddies/screens/profile_screen.dart';
import 'package:time_buddies/widgets/custom_bottom_nav.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  final List<Widget> _pages = const [
    HomePage(),
    CalendarScreen(),
    CollaborationScreen(),
    ProfileScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}
