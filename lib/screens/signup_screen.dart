import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:time_buddies/services/auth_service.dart';
import 'package:time_buddies/services/database_service.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _showEmailError = false;
  bool _showPasswordError = false;
  bool _showConfirmPasswordError = false;
  bool _showNameError = false;

  // Function to check password strength
  String _checkPasswordStrength(String password) {
    if (password.isEmpty) return '';
    if (password.length < 6) return 'Weak';
    if (password.length < 8) return 'Medium';
    if (!RegExp(r'[A-Z]').hasMatch(password)) return 'Medium';
    if (!RegExp(r'[0-9]').hasMatch(password)) return 'Medium';
    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) return 'Medium';
    return 'Strong';
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final databaseService = Provider.of<DatabaseService>(context);

    return Scaffold(
        appBar: AppBar(
          title: const Text('Sign Up'),
          automaticallyImplyLeading: false,
        ),
        backgroundColor: Colors.white,
        resizeToAvoidBottomInset: true, // Adjust layout for keyboard
        body: SafeArea(
            // Ensure content stays within safe area
            child: SingleChildScrollView(
          // Enable minimal scrolling
          padding: const EdgeInsets.all(16.0),
          child: Builder(
            // Use Builder to get a context under the Scaffold
            builder: (BuildContext context) {
              return ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height -
                      Scaffold.of(context).appBarMaxHeight! -
                      MediaQuery.of(context).padding.top,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildNameTextField(),
                    const SizedBox(height: 16),
                    _buildEmailTextField(),
                    const SizedBox(height: 16),
                    _buildPasswordTextField(),
                    const SizedBox(height: 8),
                    _buildPasswordStrengthIndicator(),
                    const SizedBox(height: 16),
                    _buildConfirmPasswordTextField(),
                    const SizedBox(height: 32),
                    _buildSignUpButton(authService, databaseService),
                    const SizedBox(height: 16),
                    const Row(
                      children: [
                        Expanded(child: Divider()),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8.0),
                          child: Text('OR'),
                        ),
                        Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildGoogleSignUpButton(authService),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () {
                        Navigator.pushReplacementNamed(context, '/login');
                      },
                      child: const Text(
                        'Already have an account? Login',
                        style: TextStyle(color: Colors.blue),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        )));
  }

  Widget _buildNameTextField() {
    return TextField(
      controller: _nameController,
      decoration: InputDecoration(
        labelText: 'Name',
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.person),
        errorText: _showNameError ? 'Name is required' : null,
      ),
      onChanged: (value) {
        setState(() {
          _showNameError = false;
        });
      },
    );
  }

  Widget _buildEmailTextField() {
    return TextField(
      controller: _emailController,
      decoration: InputDecoration(
        labelText: 'Email',
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.email),
        errorText: _showEmailError ? 'Email is required' : null,
      ),
      onChanged: (value) {
        setState(() {
          _showEmailError = false;
        });
      },
    );
  }

  Widget _buildPasswordTextField() {
    return TextField(
      controller: _passwordController,
      decoration: InputDecoration(
        labelText: 'Password',
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.lock),
        suffixIcon: IconButton(
          icon:
              Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
          onPressed: () {
            setState(() {
              _obscurePassword = !_obscurePassword;
            });
          },
        ),
        errorText: _showPasswordError ? 'Password is required' : null,
      ),
      obscureText: _obscurePassword,
      onChanged: (value) {
        setState(() {
          _showPasswordError = false;
        });
      },
    );
  }

  Widget _buildConfirmPasswordTextField() {
    return TextField(
      controller: _confirmPasswordController,
      decoration: InputDecoration(
        labelText: 'Confirm Password',
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.lock),
        suffixIcon: IconButton(
          icon: Icon(_obscureConfirmPassword
              ? Icons.visibility
              : Icons.visibility_off),
          onPressed: () {
            setState(() {
              _obscureConfirmPassword = !_obscureConfirmPassword;
            });
          },
        ),
        errorText:
            _showConfirmPasswordError ? 'Confirm Password is required' : null,
      ),
      obscureText: _obscureConfirmPassword,
      onChanged: (value) {
        setState(() {
          _showConfirmPasswordError = false;
        });
      },
    );
  }

  Widget _buildPasswordStrengthIndicator() {
    final strength = _checkPasswordStrength(_passwordController.text);
    Color strengthColor = Colors.grey;
    if (strength == 'Weak') strengthColor = Colors.red;
    if (strength == 'Medium') strengthColor = Colors.orange;
    if (strength == 'Strong') strengthColor = Colors.green;

    return Row(
      children: [
        Expanded(
          child: LinearProgressIndicator(
            value: strength == 'Weak'
                ? 0.33
                : strength == 'Medium'
                    ? 0.66
                    : 1.0,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(strengthColor),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          strength,
          style: TextStyle(color: strengthColor, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildSignUpButton(
      AuthService authService, DatabaseService databaseService) {
    return ElevatedButton(
      onPressed: () async {
        final email = _emailController.text.trim();
        final password = _passwordController.text.trim();
        final confirmPassword = _confirmPasswordController.text.trim();
        final name = _nameController.text.trim();

        // Validate fields
        setState(() {
          _showEmailError = email.isEmpty;
          _showPasswordError = password.isEmpty;
          _showConfirmPasswordError = confirmPassword.isEmpty;
          _showNameError = name.isEmpty;
        });

        if (email.isEmpty ||
            password.isEmpty ||
            confirmPassword.isEmpty ||
            name.isEmpty) {
          return; // Stop if any field is empty
        }

        if (password != confirmPassword) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Passwords do not match.'),
            ),
          );
          return;
        }

        // Sign up with email and password
        final user = await authService.signUpWithEmail(email, password);
        if (user != null) {
          // Add user to Firestore
          await databaseService.addUser(
            userID: user.uid,
            name: name,
            email: email,
            profilePicture: '', // You can add a profile picture later
          );

          // Navigate to the home screen
          // After successful login/signup
          Navigator.pushReplacementNamed(context, '/home');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sign up failed. Please try again.'),
            ),
          );
        }
      },
      style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 50),
          backgroundColor: Colors.blue),
      child: const Text(
        'Sign up with Email',
        style: TextStyle(color: Colors.white, fontSize: 16),
      ),
    );
  }

  Widget _buildGoogleSignUpButton(AuthService authService) {
    return ElevatedButton(
      onPressed: () async {
        await authService.signInWithGoogle(context);
      },
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 50),
        backgroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: const BorderSide(color: Colors.grey, width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            'assets/google_logo.png',
            height: 24,
            width: 24,
          ),
          const SizedBox(width: 12),
          const Text(
            'Sign up with Google',
            style: TextStyle(
              color: Colors.black87,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
