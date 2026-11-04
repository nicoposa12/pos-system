import 'dart:async';
import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import 'login_screen.dart';

class GetStartedScreen extends StatefulWidget {
  const GetStartedScreen({super.key});

  @override
  State<GetStartedScreen> createState() => _GetStartedScreenState();
}

class _GetStartedScreenState extends State<GetStartedScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  Timer? _timer;

  static const List<_SlideData> _slides = [
    _SlideData(
      badge: 'SMART REGISTER',
      title: 'Fast checkout built for daily hustle',
      description:
          'Ring up groceries, variants, and barcode items in seconds with quick-cash chips and GCash QR support.',
      icon: Icons.point_of_sale_rounded,
      accent: AppTheme.accentOrange,
      highlights: ['Barcode scanner', 'Variant pricing', 'Cash & GCash'],
    ),
    _SlideData(
      badge: 'STOCK CONTROL',
      title: 'Always know what needs restocking',
      description:
          'Track live stock counts across categories, spot low-stock items early, and update inventory effortlessly.',
      icon: Icons.inventory_2_rounded,
      accent: AppTheme.accentTeal,
      highlights: ['Low-stock alerts', 'Category filters', 'Quick +stock'],
    ),
    _SlideData(
      badge: 'CLEAR INSIGHTS',
      title: '100% offline sales & thermal receipts',
      description:
          'Review daily revenue trends, print or share itemized receipts, and back up your store database anytime.',
      icon: Icons.insights_rounded,
      accent: AppTheme.accentIndigo,
      highlights: ['Revenue analytics', 'Receipt printing', 'Local backup'],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _startAutoSwipe();
  }

  void _startAutoSwipe() {
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || !_pageController.hasClients) return;
      final next = (_currentPage + 1) % _slides.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceDark,
      body: Stack(
        children: [
          // Subtle ambient radial accents
          Positioned(
            top: -120,
            right: -80,
            child: IgnorePointer(
              child: Container(
                width: 340,
                height: 340,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppTheme.accentOrange.withValues(alpha: 0.16),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -140,
            left: -100,
            child: IgnorePointer(
              child: Container(
                width: 360,
                height: 360,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppTheme.accentIndigo.withValues(alpha: 0.12),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isCompactHeight = constraints.maxHeight < 640;

                    return Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: isCompactHeight ? 12 : 24,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ── Top Brand Row ──
                          Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: AppTheme.cardDark,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppTheme.borderDark),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Image.asset(
                                  'assets/images/app_icon.png',
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => const Icon(
                                    Icons.storefront_rounded,
                                    color: AppTheme.accentOrange,
                                    size: 22,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'TindaKo',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                    Text(
                                      'Point of Sale & Inventory',
                                      style: TextStyle(
                                        color: AppTheme.textSecondaryDark,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.accentTeal.withValues(
                                    alpha: 0.14,
                                  ),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: AppTheme.accentTeal.withValues(
                                      alpha: 0.35,
                                    ),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.offline_bolt_rounded,
                                      size: 14,
                                      color: AppTheme.accentTeal,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      'Offline-Ready',
                                      style: TextStyle(
                                        color: AppTheme.accentTeal,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          SizedBox(height: isCompactHeight ? 12 : 24),

                          // ── Feature Carousel ──
                          Expanded(
                            child: PageView.builder(
                              controller: _pageController,
                              itemCount: _slides.length,
                              onPageChanged: (index) {
                                setState(() => _currentPage = index);
                              },
                              itemBuilder: (context, index) {
                                return _OnboardingSlideCard(
                                  slide: _slides[index],
                                  compact: isCompactHeight,
                                );
                              },
                            ),
                          ),

                          SizedBox(height: isCompactHeight ? 12 : 20),

                          // ── Page Indicator Dots ──
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(_slides.length, (index) {
                              final isActive = _currentPage == index;
                              return GestureDetector(
                                onTap: () {
                                  _pageController.animateToPage(
                                    index,
                                    duration: const Duration(milliseconds: 350),
                                    curve: Curves.easeOutCubic,
                                  );
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  height: 6,
                                  width: isActive ? 28 : 8,
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? AppTheme.accentOrange
                                        : AppTheme.borderDark,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                              );
                            }),
                          ),

                          SizedBox(height: isCompactHeight ? 16 : 28),

                          // ── Primary CTA ──
                          SizedBox(
                            height: 54,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const LoginScreen(),
                                  ),
                                );
                              },
                              icon: const Icon(
                                Icons.login_rounded,
                                size: 20,
                              ),
                              label: const Text('Sign In to Register'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.accentOrange,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // ── Administrator Managed Note ──
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.admin_panel_settings_outlined,
                                    size: 15,
                                    color: AppTheme.textSecondaryDark,
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      'Accounts are provisioned by Administrator',
                                      style: TextStyle(
                                        color: AppTheme.textSecondaryDark.withValues(alpha: 0.8),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SlideData {
  final String badge;
  final String title;
  final String description;
  final IconData icon;
  final Color accent;
  final List<String> highlights;

  const _SlideData({
    required this.badge,
    required this.title,
    required this.description,
    required this.icon,
    required this.accent,
    required this.highlights,
  });
}

class _OnboardingSlideCard extends StatelessWidget {
  final _SlideData slide;
  final bool compact;

  const _OnboardingSlideCard({
    required this.slide,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Container(
          padding: EdgeInsets.all(compact ? 20 : 28),
          decoration: BoxDecoration(
            color: AppTheme.cardDark,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppTheme.borderDark),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: compact ? 48 : 56,
                    height: compact ? 48 : 56,
                    decoration: BoxDecoration(
                      color: slide.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: slide.accent.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Icon(
                      slide.icon,
                      color: slide.accent,
                      size: compact ? 24 : 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceDark,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.borderDark),
                      ),
                      child: Text(
                        slide.badge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: slide.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 16 : 24),
              Text(
                slide.title,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 24 : 30,
                  height: 1.18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                slide.description,
                style: TextStyle(
                  color: AppTheme.textSecondaryDark,
                  fontSize: compact ? 14 : 15,
                  height: 1.55,
                ),
              ),
              SizedBox(height: compact ? 16 : 22),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: slide.highlights.map((chip) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceDark,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.borderDark),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          size: 14,
                          color: slide.accent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          chip,
                          style: const TextStyle(
                            color: AppTheme.textPrimaryDark,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
