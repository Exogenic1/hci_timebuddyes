import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:time_buddies/screens/group_chat_screen.dart';
import 'package:time_buddies/services/notifications_service.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/home.dart';
import 'services/auth_service.dart';
import 'services/database_service.dart';

// Global key for navigation
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final NotificationService _notificationService = NotificationService();

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
  }

  Future<void> _initializeNotifications() async {
    // Initialize notification settings
    await _notificationService.initializeSettings();

    // Handle foreground notifications
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        debugPrint(
            'Foreground notification received: ${message.notification!.body}');
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (context) => AlertDialog(
              title: Text(message.notification!.title ?? 'Notification'),
              content: Text(
                  message.notification!.body ?? 'You have a new notification'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          ),
        );
      }
    });

    // Handle background notifications when the app is opened
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      if (message.data['chatId'] != null) {
        navigatorKey.currentState?.pushNamed(
          '/chat',
          arguments: message.data['chatId'],
        );
      }
    });

    // Update FCM token for the current user
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await _notificationService.updateFcmToken(user.uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AuthService>(create: (_) => AuthService()),
        Provider<DatabaseService>(create: (_) => DatabaseService()),
        Provider<NotificationService>(create: (_) => _notificationService),
      ],
      child: MaterialApp(
        title: 'TimeBuddies',
        theme: ThemeData(primarySwatch: Colors.blue),
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey, // Assign the global key
        home: const AuthWrapper(),
        routes: {
          '/login': (context) => const LoginScreen(),
          '/signup': (context) => const SignupScreen(),
          '/home': (context) => const HomeScreen(),
          '/chat': (context) {
            final chatId = ModalRoute.of(context)!.settings.arguments as String;
            return GroupChatScreen(
              chatId: chatId,
              groupName: 'Chat',
              currentUserId: FirebaseAuth.instance.currentUser!.uid,
              currentUserName:
                  FirebaseAuth.instance.currentUser!.displayName ?? 'User',
              groupLeaderId: 'leaderId',
            );
          },
        },
      ),
    );
  }
}

// AuthWrapper remains unchanged
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    return StreamBuilder<User?>(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.active) {
          final user = snapshot.data;
          if (user != null) {
            return const HomeScreen(key: ValueKey('homeScreen'));
          } else {
            return const LoginScreen(key: ValueKey('loginScreen'));
          }
        }
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}
