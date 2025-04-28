import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:time_buddies/screens/group_chat_screen.dart';
import 'package:time_buddies/services/notification_processor.dart';
import 'package:time_buddies/services/notifications_service.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/home.dart';
import 'services/auth_service.dart';
import 'services/database_service.dart';

// Global key for navigation
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// This handler needs to be defined at the top level for background message handling
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await NotificationService().initialize();
  await NotificationService().showLocalNotificationFromMessage(message);
}

void main() async {
  tz.initializeTimeZones();
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await NotificationService().initialize();

  // Register the background handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

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
    await _notificationService.initialize();
    await _notificationService.initializeSettings();

    // Set up foreground notification handler to show dialog
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _notificationService.showLocalNotificationFromMessage(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleNotificationTap(message);
    });

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }
  }

  void _handleNotificationTap(RemoteMessage message) {
    if (message.data['taskId'] != null) {
      navigatorKey.currentState?.pushNamed(
        '/task',
        arguments: message.data['taskId'],
      );
    } else if (message.data['chatId'] != null) {
      navigatorKey.currentState?.pushNamed(
        '/chat',
        arguments: message.data['chatId'],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AuthService>(create: (_) => AuthService()),
        Provider<DatabaseService>(create: (_) => DatabaseService()),
        Provider<NotificationService>(create: (_) => NotificationService()),
        Provider<NotificationProcessor>(
          create: (context) => NotificationProcessor(
            Provider.of<NotificationService>(context, listen: false),
          ),
        ),
        // Add stream provider for notification badge count
        StreamProvider<int>(
          create: (_) => _notificationService.notificationCountStream,
          initialData: 0,
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
          // '/task': (context) {
          //   final taskId = ModalRoute.of(context)!.settings.arguments as String;
          //   return TaskDetailScreen(taskId: taskId);
          // },
        },
      ),
    );
  }
}

// AuthWrapper with updated method name
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final notificationService =
        Provider.of<NotificationService>(context, listen: false);

    return StreamBuilder<User?>(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.active) {
          final user = snapshot.data;
          if (user != null) {
            // Initialize notifications with user ID using the correct method name
            notificationService.initializeForUser(user.uid);
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
