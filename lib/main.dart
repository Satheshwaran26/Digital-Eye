import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:my_app/screens/get_started_screen.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/parent/parent_home_screen.dart';
import 'screens/child/child_home_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  tz.initializeTimeZones();
  final FlutterLocalNotificationsPlugin notifications =
      FlutterLocalNotificationsPlugin();
  const AndroidInitializationSettings initSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initSettings =
      InitializationSettings(android: initSettingsAndroid);
  await notifications.initialize(initSettings);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Digital Wellbeing',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.light,
        ),
        useMaterial3: true,fontFamily: 'Poppins',
        textTheme: const TextTheme(
          displayLarge:
              TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold),
          displayMedium:
              TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600),
          bodyLarge:
              TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.normal),
          bodyMedium:
              TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.normal),
          titleLarge:
              TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600),
          titleMedium:
              TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w500),
        ),
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.active) {
            final user = snapshot.data;
            if (user == null) {
              return GetStartedScreen();
            }
            // Check if user is parent or child via Firestore
            return FutureBuilder(
              future: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .get(),
              builder: (context, AsyncSnapshot<DocumentSnapshot> snapshot) {
                if (snapshot.connectionState == ConnectionState.done) {
                  if (snapshot.data?.exists ?? false) {
                    final isParent = snapshot.data?['isParent'] ?? false;
                    return isParent
                        ? const ParentHomeScreen()
                        : const ChildHomeScreen(
                            qrCodeId: '',
                          );
                  }
                  return GetStartedScreen();
                }
                return const Center(child: CircularProgressIndicator());
              },
            );
          }
          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }
}
