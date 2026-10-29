import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'brand_widgets.dart';

import 'main.dart';
import 'catalog_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.bookings, required this.onBooked});

  final List<MovieBooking> bookings;
  final ValueChanged<MovieBooking> onBooked;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const primaryPurple = Color(0xFF8B5CF6);
  static const fieldFill = Color(0xFFF3F1FA);

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool _busy = false;
  bool _register = false;
  bool _obscurePassword = true;
  String? _error;
  final _service = CatalogService();

  void _switchMode() {
    setState(() {
      _register = !_register;
      _error = null;
    });
  }

  Future<void> _signIn() async {
    if (!(_formKey.currentState?.validate() ?? false) || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.signIn(
        _emailController.text.trim(),
        _passwordController.text,
        register: _register,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => HomeShell(
            bookings: widget.bookings,
            onBooked: widget.onBooked,
            catalogService: _service,
          ),
        ),
      );
    } on CatalogException catch (e) {
      if (mounted) {
        setState(
          () =>
              _error = !_register && e.message == 'Incorrect email or password.'
              ? 'Incorrect email or password. New customers must create an account first.'
              : e.message,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The app theme is dark, but this page is white, so ask for dark
    // status-bar icons here (otherwise they're white-on-white and invisible).
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Center(
            // Scrollable so the keyboard can't push the form off-screen
            // (prevents a "bottom overflowed" error on small phones).
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 28),
                      child: MovieSeatLogo(
                        width: 320,
                        height: 112,
                        onDark: false,
                      ),
                    ),
                    const SizedBox(height: 8),

                    Text(
                      _register ? 'Create your account' : 'Welcome back',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.black54,
                        letterSpacing: 0.4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    const SizedBox(height: 28),

                    _buildField(
                      controller: _emailController,
                      hintText: 'Email',
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        final email = value?.trim() ?? '';
                        if (email.isEmpty) return 'Please enter your email';
                        if (!email.contains('@') || !email.contains('.')) {
                          return 'Please enter a valid email';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 10),

                    _buildField(
                      controller: _passwordController,
                      hintText: 'Password',
                      obscureText: _obscurePassword,
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword
                            ? 'Show password'
                            : 'Hide password',
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: Colors.black54,
                        ),
                      ),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _signIn(),
                      validator: (value) {
                        if ((value ?? '').length < 8) {
                          return 'Use at least 8 characters';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 10),

                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    if (_busy) const LinearProgressIndicator(),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 25,
                        vertical: 12,
                      ),
                      child: Text(
                        _register
                            ? 'Use at least 8 characters for your password.'
                            : 'Sign in to book your next movie night.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 25),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _busy ? null : _signIn,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF7C3AED),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(56),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _busy
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  _register ? 'Create account' : 'Sign In',
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 25),

                    // Register
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          _register ? 'Already a member? ' : 'Not a member? ',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.black54,
                          ),
                        ),
                        TextButton(
                          onPressed: _busy ? null : _switchMode,
                          style: TextButton.styleFrom(
                            foregroundColor: primaryPurple,
                          ),
                          child: Text(
                            _register ? 'Sign in' : 'Register now',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String hintText,
    required FormFieldValidator<String> validator,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
  }) {
    const fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      borderSide: BorderSide(color: Color(0x14000000)),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25.0),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        onFieldSubmitted: onSubmitted,
        validator: validator,
        enabled: !_busy,
        autofillHints: [
          hintText == 'Email'
              ? AutofillHints.email
              : _register
              ? AutofillHints.newPassword
              : AutofillHints.password,
        ],
        autocorrect: false,
        style: const TextStyle(color: Colors.black87),
        decoration: InputDecoration(
          filled: true,
          fillColor: fieldFill,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 18,
          ),
          labelText: hintText,
          labelStyle: const TextStyle(color: Colors.black54),
          hintText: hintText == 'Email' ? 'you@example.com' : null,
          suffixIcon: suffixIcon,
          hintStyle: const TextStyle(color: Colors.black38),
          enabledBorder: fieldBorder,
          focusedBorder: fieldBorder.copyWith(
            borderSide: const BorderSide(color: primaryPurple, width: 1.5),
          ),
          errorBorder: fieldBorder.copyWith(
            borderSide: const BorderSide(color: Colors.redAccent),
          ),
          focusedErrorBorder: fieldBorder.copyWith(
            borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
          ),
          errorStyle: const TextStyle(color: Colors.redAccent),
        ),
      ),
    );
  }
}
