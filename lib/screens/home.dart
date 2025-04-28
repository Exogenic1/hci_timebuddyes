import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:time_buddies/screens/home_page.dart';
import 'package:time_buddies/screens/calendar/calendar_screen.dart';
import 'package:time_buddies/screens/collaboration_screen.dart';
import 'package:time_buddies/screens/profile_screen.dart';
import 'package:time_buddies/services/notification_processor.dart';
import 'package:time_buddies/services/notifications_service.dart';
import 'package:time_buddies/widgets/custom_bottom_nav.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  final PageController _pageController = PageController();
  StreamSubscription<User?>? _authSubscription;

  // Use ValueKey to force rebuild when auth state changes
  final List<Widget> _pages = [
    const HomePage(key: ValueKey('homePage')),
    const CalendarScreen(key: ValueKey('calendarPage')),
    const CollaborationScreen(key: ValueKey('collabPage')),
    const ProfileScreen(key: ValueKey('profilePage')),
  ];

  @override
  void initState() {
    super.initState();
    // Listen to auth state changes
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        // Handle logout if needed
      } else {
        // Force rebuild when user relogs
        if (mounted) {
          setState(() {
            // This will force the pages to rebuild with fresh data
          });
        }
      }
    });
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    _pageController.jumpToPage(index);
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Disables the back button
      child: Scaffold(
        body: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          children: _pages,
          onPageChanged: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
        ),
        bottomNavigationBar: CustomBottomNavBar(
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
        ),
      ),
    );
  }
}
