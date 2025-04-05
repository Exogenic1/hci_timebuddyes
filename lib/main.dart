import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
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
  final NotificationsService _notificationsService = NotificationsService();

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
  }

  // Add this in your main.dart (where you initialize the app)
  Future<void> _initializeNotifications() async {
    await _notificationsService.initialize(
      onMessageCallback: (message) {
        // Handle the notification (will work even without context)
        debugPrint('Received notification: ${message.notification?.body}');

        // If you need to show UI, use the navigatorKey approach
        if (message.notification != null) {
          navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (context) => AlertDialog(
                title: const Text('New Notification'),
                content: Text(message.notification!.body ?? ''),
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
      },
    );
  }

  void _handleNotification(RemoteMessage message) {
    // Only handle if the app is in foreground
    if (message.notification != null) {
      // Show a dialog or snackbar using the navigatorKey
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => AlertDialog(
            title: Text(message.notification?.title ?? 'New Message'),
            content:
                Text(message.notification?.body ?? 'You have a new message'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  // Navigate to specific screen if needed
                  if (message.data['chatId'] != null) {
                    navigatorKey.currentState?.pushNamed(
                      '/chat',
                      arguments: message.data['chatId'],
                    );
                  }
                },
                child: const Text('OK'),
              ),
            ],
          ),
          fullscreenDialog: true,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AuthService>(create: (_) => AuthService()),
        Provider<DatabaseService>(create: (_) => DatabaseService()),
        Provider<NotificationsService>(
          create: (_) => _notificationsService,
        ),
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
          // Add your chat route if not already present
          '/chat': (context) {
            final chatId = ModalRoute.of(context)!.settings.arguments as String;
            return GroupChatScreen(
              chatId: chatId,
              groupName: 'Chat', // You might want to fetch the actual name
              currentUserId: FirebaseAuth.instance.currentUser!.uid,
              currentUserName: 'User', // Fetch actual username
              groupLeaderId:
                  'leaderId', // Replace 'leaderId' with the actual leader ID
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
            return const HomeScreen();
          } else {
            return const LoginScreen();
          }
        } else {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
      },
    );
  }
}
