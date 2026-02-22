import 'package:flutter/material.dart';

import 'package:ren/shared/widgets/ren_logo.dart';
import 'package:ren/shared/widgets/animated_gradient.dart';
import 'package:ren/shared/widgets/glass_surface.dart';
import 'package:ren/shared/widgets/glass_snackbar.dart';

import 'package:ren/features/auth/presentation/components/signin.dart';
import 'package:ren/features/auth/presentation/components/signup.dart';
import 'package:ren/features/auth/presentation/components/recovery.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({Key? key}) : super(key: key);

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> with TickerProviderStateMixin {
  late AnimationController _backgroundController;
  late AnimationController _formController;
  late Animation<double> _backgroundAnimation;
  late Animation<double> _formAnimation;
  late AnimationController _solarSystemController;

  int _selectedTab = 0; // 0 - вход, 1 - регистрация, 2 - забыл пароль

  @override
  void initState() {
    super.initState();

    _backgroundController = AnimationController(
      duration: const Duration(seconds: 12),
      vsync: this,
    )..repeat();

    _formController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _backgroundAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_backgroundController);

    _formAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _formController, curve: Curves.easeOutCubic),
    );

    _solarSystemController = AnimationController(
      duration: const Duration(seconds: 15),
      vsync: this,
    )..repeat();

    _formController.forward();
  }

  @override
  void dispose() {
    _backgroundController.dispose();
    _formController.dispose();
    _solarSystemController.dispose();
    super.dispose();
  }

  void _changeTab(int tab) {
    if (tab != _selectedTab) {
      _formController.reverse().then((_) {
        setState(() {
          _selectedTab = tab;
        });
        _formController.forward();
      });
    }
  }

  void _handleRegistrationSuccess() {
    _changeTab(0);
    Future<void>.delayed(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      showGlassSnack(
        context,
        'Регистрация успешна. Теперь войдите в аккаунт.',
        kind: GlassSnackKind.success,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: AnimatedBuilder(
        animation: _backgroundAnimation,
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              gradient: AnimatedGradientUtils.buildAnimatedGradient(
                _backgroundAnimation.value,
                isDark,
                primaryColor: theme.colorScheme.primary,
                secondaryColor: theme.colorScheme.secondary,
              ),
            ),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final horizontalPadding = (constraints.maxWidth * 0.08).clamp(
                    16.0,
                    28.0,
                  );
                  final outerVerticalPadding = (constraints.maxHeight * 0.03)
                      .clamp(12.0, 24.0);
                  final logoSize = constraints.maxWidth < 360
                      ? 104.0
                      : constraints.maxWidth > 520
                      ? 128.0
                      : 120.0;
                  final headerBottomSpacing = constraints.maxHeight < 700
                      ? 20.0
                      : 30.0;
                  final formBottomSpacing = constraints.maxHeight < 700
                      ? 12.0
                      : 16.0;
                  final cardPadding = constraints.maxWidth < 360 ? 16.0 : 20.0;
                  final cardSectionSpacing = constraints.maxWidth < 360
                      ? 16.0
                      : 20.0;
                  final formHorizontalPadding = constraints.maxWidth < 360
                      ? 4.0
                      : 8.0;
                  final footerTopSpacing = constraints.maxWidth < 360
                      ? 12.0
                      : 16.0;
                  return ScrollConfiguration(
                    behavior: const ScrollBehavior().copyWith(
                      overscroll: false,
                    ),
                    child: SingleChildScrollView(
                      padding: EdgeInsets.zero,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: horizontalPadding,
                              vertical: outerVerticalPadding,
                            ),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 400),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(height: outerVerticalPadding),
                                  _buildHeader(isDark, logoSize: logoSize),
                                  SizedBox(height: headerBottomSpacing),
                                  AnimatedBuilder(
                                    animation: _formAnimation,
                                    builder: (context, child) {
                                      return Transform.translate(
                                        offset: Offset(
                                          0,
                                          (1 - _formAnimation.value) * 30,
                                        ),
                                        child: Opacity(
                                          opacity: _formAnimation.value,
                                          child: _buildMainCard(
                                            isDark,
                                            cardPadding: cardPadding,
                                            cardSectionSpacing:
                                                cardSectionSpacing,
                                            formHorizontalPadding:
                                                formHorizontalPadding,
                                            footerTopSpacing: footerTopSpacing,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  SizedBox(height: formBottomSpacing),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(bool isDark, {required double logoSize}) {
    return Column(
      children: [
        SizedBox(
          width: logoSize,
          height: logoSize,
          child: RenLogo(
            size: logoSize,
            controller: _solarSystemController,
            fontSize: logoSize * 0.12,
            strokeWidth: logoSize < 110 ? 0.9 : 1.0,
            dotRadius: logoSize < 110 ? 2.2 : 2.5,
          ),
        ),
      ],
    );
  }

  Widget _buildMainCard(
    bool isDark, {
    required double cardPadding,
    required double cardSectionSpacing,
    required double formHorizontalPadding,
    required double footerTopSpacing,
  }) {
    return GlassSurface(
      borderRadius: 24,
      blurSigma: 18,
      padding: EdgeInsets.all(cardPadding),
      borderColor: isDark
          ? Colors.white.withOpacity(0.15)
          : Colors.white.withOpacity(0.4),
      boxShadow: [
        BoxShadow(
          color: isDark
              ? Colors.black.withOpacity(0.3)
              : Colors.black.withOpacity(0.08),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ],
      child: Column(
        children: [
          _buildTabBar(isDark),
          SizedBox(height: cardSectionSpacing),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: formHorizontalPadding),
            child: _buildCurrentForm(),
          ),
          if (_selectedTab != 2) ...[
            SizedBox(height: footerTopSpacing),
            _buildForgotPasswordButton(isDark),
          ],
        ],
      ),
    );
  }

  Widget _buildTabBar(bool isDark) {
    return GlassSurface(
      borderRadius: 23,
      blurSigma: 14,
      height: 46,
      padding: const EdgeInsets.all(3),
      borderWidth: 0.5,
      borderColor: isDark
          ? Colors.white.withOpacity(0.1)
          : Colors.white.withOpacity(0.25),
      child: Row(
        children: [
          _buildTabItem('Вход', 0, isDark),
          _buildTabItem('Регистрация', 1, isDark),
        ],
      ),
    );
  }

  Widget _buildTabItem(String title, int index, bool isDark) {
    final isSelected = _selectedTab == index;
    final theme = Theme.of(context);

    return Expanded(
      child: GestureDetector(
        onTap: () => _changeTab(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: isSelected
                ? (isDark
                      ? Colors.white.withOpacity(0.15)
                      : Colors.white.withOpacity(0.5))
                : Colors.transparent,
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: isDark
                          ? Colors.black.withOpacity(0.2)
                          : Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.w300,
                  color: isSelected
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurface.withOpacity(0.65),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentForm() {
    switch (_selectedTab) {
      case 0:
        return const SignInForm();
      case 1:
        return SignUpForm(onRegistrationSuccess: _handleRegistrationSuccess);
      case 2:
        return const ForgotPasswordForm();
      default:
        return const SignInForm();
    }
  }

  Widget _buildForgotPasswordButton(bool isDark) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => _changeTab(2),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
        child: Text(
          'Забыли пароль?',
          style: TextStyle(
            color: theme.colorScheme.onSurface.withOpacity(0.65),
            fontSize: 14,
            fontWeight: FontWeight.w300,
            decoration: TextDecoration.underline,
            decorationColor: theme.colorScheme.onSurface.withOpacity(0.45),
          ),
        ),
      ),
    );
  }
}
