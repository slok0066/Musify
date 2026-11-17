import 'package:flutter/material.dart';

import '../../../core/theme/swiss_tokens.dart';
import '../../../core/theme/tactile_decorations.dart';
import '../../widgets/swiss_artwork.dart';

/// Representation of an artist displayed during onboarding.
class OnboardingArtist {
  const OnboardingArtist({
    required this.name,
    required this.category,
    required this.imageUrl,
  });

  final String name;
  final String category;
  final String imageUrl;
}

/// Clean and minimal Artist Onboarding Screen shown after the Name entry screen.
///
/// Triggers strictly once upon fresh installation when `selectedArtists` is empty.
/// Persisting either selected artists or `['skipped']` ensures it is never displayed again.
class ArtistOnboardingScreen extends StatefulWidget {
  const ArtistOnboardingScreen({
    required this.onComplete,
    super.key,
  });

  final ValueChanged<List<String>> onComplete;

  static const List<OnboardingArtist> catalog = [
    // Hindi
    OnboardingArtist(
      name: 'Arijit Singh',
      category: 'Hindi',
      imageUrl: 'https://c.saavncdn.com/artists/Arijit_Singh_004_20241118063717_500x500.jpg',
    ),
    OnboardingArtist(
      name: 'Shreya Ghoshal',
      category: 'Hindi',
      imageUrl: 'https://c.saavncdn.com/artists/Shreya_Ghoshal_007_20241101074144_500x500.jpg',
    ),
    OnboardingArtist(
      name: 'Atif Aslam',
      category: 'Hindi',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/0ea90444148fff9c11d77f06a344724e/1000x1000-000000-80-0-0.jpg',
    ),
    OnboardingArtist(
      name: 'Pritam',
      category: 'Hindi',
      imageUrl: 'https://c.saavncdn.com/artists/Pritam_Chakraborty-20170711073326_500x500.jpg',
    ),
    OnboardingArtist(
      name: 'Vishal Mishra',
      category: 'Hindi',
      imageUrl: 'https://c.saavncdn.com/artists/Vishal_Mishra_005_20251120085316_500x500.jpg',
    ),
    OnboardingArtist(
      name: 'Darshan Raval',
      category: 'Hindi',
      imageUrl: 'https://c.saavncdn.com/artists/Darshan_Raval_006_20250807060352_500x500.jpg',
    ),
    OnboardingArtist(
      name: 'Mohit Chauhan',
      category: 'Hindi',
      imageUrl: 'https://c.saavncdn.com/artists/Mohit_Chauhan_500x500.jpg',
    ),
    OnboardingArtist(
      name: 'Jubin Nautiyal',
      category: 'Hindi',
      imageUrl: 'https://c.saavncdn.com/artists/Jubin_Nautiyal_003_20231130204020_500x500.jpg',
    ),

    // Punjabi
    OnboardingArtist(
      name: 'Diljit Dosanjh',
      category: 'Punjabi',
      imageUrl: 'https://c.saavncdn.com/artists/Diljit_Dosanjh_005_20231025073054_500x500.jpg',
    ),
    OnboardingArtist(
      name: 'Sidhu Moosewala',
      category: 'Punjabi',
      imageUrl: 'https://c.saavncdn.com/artists/Sidhu_Moose_Wala_004_20250617183705_500x500.jpg',
    ),
    OnboardingArtist(
      name: 'Karan Aujla',
      category: 'Punjabi',
      imageUrl: 'https://c.saavncdn.com/artists/Karan_Aujla_005_20260925061936_500x500.jpg',
    ),
    OnboardingArtist(
      name: 'AP Dhillon',
      category: 'Punjabi',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/52594ac9fa763dc163ed13d21cb130ec/1000x1000-000000-80-0-0.jpg',
    ),
    OnboardingArtist(
      name: 'Shubh',
      category: 'Punjabi',
      imageUrl: 'https://c.saavncdn.com/artists/Shubh_000_20220921112507_500x500.jpg',
    ),
    OnboardingArtist(
      name: 'Guru Randhawa',
      category: 'Punjabi',
      imageUrl: 'https://c.saavncdn.com/artists/Guru_Randhawa_005_20261026140443_500x500.jpg',
    ),

    // English / Pop
    OnboardingArtist(
      name: 'The Weeknd',
      category: 'English',
      imageUrl: 'https://c.saavncdn.com/artists/The_Weeknd_002_20241003071400_500x500.jpg',
    ),
    OnboardingArtist(
      name: 'Taylor Swift',
      category: 'English',
      imageUrl: 'https://c.saavncdn.com/artists/Taylor_Swift_003_20200226074119_500x500.jpg',
    ),
    OnboardingArtist(
      name: 'Billie Eilish',
      category: 'English',
      imageUrl: 'https://c.saavncdn.com/artists/Billie_Eilish_20190211151539_500x500.jpg',
    ),
    OnboardingArtist(
      name: 'Bruno Mars',
      category: 'English',
      imageUrl: 'https://c.saavncdn.com/artists/Bruno_Mars_003_20260324060413_500x500.jpg',
    ),
    OnboardingArtist(
      name: 'Dua Lipa',
      category: 'English',
      imageUrl: 'https://c.saavncdn.com/artists/Dua_Lipa_004_20231120090922_500x500.jpg',
    ),
    OnboardingArtist(
      name: 'Drake',
      category: 'English',
      imageUrl: 'https://c.saavncdn.com/artists/Drake_006_20260520062317_500x500.jpg',
    ),
    OnboardingArtist(
      name: 'Ed Sheeran',
      category: 'English',
      imageUrl: 'https://c.saavncdn.com/artists/Ed_Sheeran_002_20250625073038_500x500.jpg',
    ),

    // Hip-Hop
    OnboardingArtist(
      name: 'DIVINE',
      category: 'Hip-Hop',
      imageUrl: 'https://c.saavncdn.com/artists/DIVINE_006_20250911071442_500x500.jpg',
    ),
    OnboardingArtist(
      name: 'Seedhe Maut',
      category: 'Hip-Hop',
      imageUrl: 'https://c.saavncdn.com/artists/Seedhe_Maut_004_20250527085239_500x500.jpg',
    ),
    OnboardingArtist(
      name: 'KR\$NA',
      category: 'Hip-Hop',
      imageUrl: 'https://c.saavncdn.com/artists/Krsna_Solo_003_20230223094118_500x500.jpg',
    ),
    OnboardingArtist(
      name: 'Travis Scott',
      category: 'Hip-Hop',
      imageUrl: 'https://c.saavncdn.com/artists/Travis_Scott_20190823072138_500x500.jpg',
    ),
    OnboardingArtist(
      name: 'Kendrick Lamar',
      category: 'Hip-Hop',
      imageUrl: 'https://c.saavncdn.com/artists/Kendrick_Lamar_500x500.jpg',
    ),

    // South
    OnboardingArtist(
      name: 'Anirudh Ravichander',
      category: 'South',
      imageUrl: 'https://c.saavncdn.com/artists/Anirudh_Ravichander_003_20260121134149_500x500.jpg',
    ),
    OnboardingArtist(
      name: 'A.R. Rahman',
      category: 'South',
      imageUrl: 'https://c.saavncdn.com/artists/AR_Rahman_002_20210120084455_500x500.jpg',
    ),
    OnboardingArtist(
      name: 'Sid Sriram',
      category: 'South',
      imageUrl: 'https://c.saavncdn.com/artists/Sid_Sriram_005_20240425180600_500x500.jpg',
    ),
    OnboardingArtist(
      name: 'Yuvan Shankar Raja',
      category: 'South',
      imageUrl: 'https://c.saavncdn.com/artists/Yuvan_Shankar_Raja_002_20180802174245_500x500.jpg',
    ),
  ];

  @override
  State<ArtistOnboardingScreen> createState() => _ArtistOnboardingScreenState();
}

class _ArtistOnboardingScreenState extends State<ArtistOnboardingScreen> {
  final Set<String> _selected = <String>{};
  final TextEditingController _searchCtrl = TextEditingController();
  String _selectedCategory = 'All';
  String _searchQuery = '';

  static const List<String> _categories = [
    'All',
    'Hindi',
    'Punjabi',
    'English',
    'Hip-Hop',
    'South',
  ];

  static const int _minRequired = 3;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggleArtist(String name) {
    Haptics.tap();
    setState(() {
      if (_selected.contains(name)) {
        _selected.remove(name);
      } else {
        _selected.add(name);
      }
    });
  }

  void _skip() {
    Haptics.tap();
    // Persist 'skipped' sentinel so the state is non-empty and will never open again.
    widget.onComplete(const ['skipped']);
  }

  void _submit() {
    if (_selected.length < _minRequired) return;
    Haptics.press();
    widget.onComplete(_selected.toList());
  }

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final topPadding = MediaQuery.paddingOf(context).top;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    final filtered = ArtistOnboardingScreen.catalog.where((item) {
      final matchesCategory = _selectedCategory == 'All' || item.category == _selectedCategory;
      final matchesQuery = _searchQuery.isEmpty ||
          item.name.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesCategory && matchesQuery;
    }).toList();

    final count = _selected.length;
    final canContinue = count >= _minRequired;

    return Scaffold(
      backgroundColor: t.bg,
      body: Stack(
        children: [
          // Scrollable Grid View
          CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              // Top Spacing & Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, topPadding + 12, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top Row: Step Tag + Skip Button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: t.surfaceSunken,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: t.hairline, width: 1),
                            ),
                            child: Text(
                              'STEP 2 OF 2',
                              style: SwissType.label.copyWith(
                                color: t.inkMuted,
                                fontSize: 10,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: _skip,
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: t.surfaceSunken,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: t.hairline, width: 1),
                              ),
                              child: Text(
                                'Skip',
                                style: TextStyle(
                                  fontFamily: 'PlusJakartaSans',
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: t.inkMuted,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Main Title
                      Text(
                        'Choose your\nfavorite artists',
                        style: TextStyle(
                          fontFamily: 'PlusJakartaSans',
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: t.ink,
                          height: 1.15,
                          letterSpacing: -0.5,
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Subtitle
                      Text(
                        'Select 3 or more to personalize your daily mixes, recommended songs & home vista.',
                        style: TextStyle(
                          fontFamily: 'PlusJakartaSans',
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: t.inkMuted,
                          height: 1.4,
                        ),
                      ),

                      const SizedBox(height: 18),

                      // Search Bar
                      Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: t.surfaceSunken,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: t.hairline, width: 1),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Row(
                          children: [
                            Icon(Icons.search_rounded, size: 18, color: t.inkFaint),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _searchCtrl,
                                style: TextStyle(
                                  fontFamily: 'PlusJakartaSans',
                                  fontSize: 13.5,
                                  color: t.ink,
                                  fontWeight: FontWeight.w600,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Search artists, bands, singers...',
                                  hintStyle: TextStyle(
                                    fontFamily: 'PlusJakartaSans',
                                    color: t.inkFaint,
                                    fontSize: 13,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                                onChanged: (q) => setState(() => _searchQuery = q.trim()),
                              ),
                            ),
                            if (_searchQuery.isNotEmpty)
                              GestureDetector(
                                onTap: () {
                                  _searchCtrl.clear();
                                  setState(() => _searchQuery = '');
                                },
                                child: Icon(Icons.close_rounded, size: 16, color: t.inkMuted),
                              ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Genre Filter Chips
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _categories.map((cat) {
                            final isActive = _selectedCategory == cat;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: GestureDetector(
                                onTap: () {
                                  Haptics.tap();
                                  setState(() => _selectedCategory = cat);
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: isActive ? t.ink : t.surfaceSunken,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: isActive ? t.ink : t.hairline,
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    cat,
                                    style: TextStyle(
                                      fontFamily: 'PlusJakartaSans',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isActive ? t.bg : t.inkMuted,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Artist Grid
              if (filtered.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text(
                        'No artists found matching "$_searchQuery"',
                        style: TextStyle(
                          fontFamily: 'PlusJakartaSans',
                          fontSize: 13,
                          color: t.inkFaint,
                        ),
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: MediaQuery.sizeOf(context).width < 340 ? 2 : 3,
                      childAspectRatio: 0.70,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final artist = filtered[index];
                        final isSelected = _selected.contains(artist.name);

                        return GestureDetector(
                          onTap: () => _toggleArtist(artist.name),
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected ? t.surfaceRaised : t.surfaceSunken,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: isSelected ? t.ink : t.hairline,
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Circular Avatar with Selection Checkmark
                                Stack(
                                  clipBehavior: Clip.none,
                                  alignment: Alignment.center,
                                  children: [
                                    Container(
                                      width: 76,
                                      height: 76,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: isSelected ? t.ink : Colors.transparent,
                                          width: 2.0,
                                        ),
                                      ),
                                      padding: const EdgeInsets.all(2.5),
                                      child: ClipOval(
                                        child: SwissArtwork(
                                          imageUrl: artist.imageUrl,
                                          size: 71,
                                          circular: true,
                                          showBorder: false,
                                          placeholderIcon: Icons.person_rounded,
                                        ),
                                      ),
                                    ),
                                    if (isSelected)
                                      Positioned(
                                        bottom: -1,
                                        right: -1,
                                        child: Container(
                                          width: 22,
                                          height: 22,
                                          decoration: BoxDecoration(
                                            color: t.ink,
                                            shape: BoxShape.circle,
                                            border: Border.all(color: t.bg, width: 2.0),
                                          ),
                                          child: Icon(
                                            Icons.check_rounded,
                                            size: 14,
                                            color: t.bg,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),

                                const SizedBox(height: 8),

                                // Artist Name
                                Text(
                                  artist.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'PlusJakartaSans',
                                    fontSize: 12.5,
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                    color: isSelected ? t.ink : t.inkMuted,
                                  ),
                                ),

                                const SizedBox(height: 2),

                                // Category / Language
                                Text(
                                  artist.category,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'PlusJakartaSans',
                                    fontSize: 10,
                                    color: t.inkFaint,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                      childCount: filtered.length,
                      addRepaintBoundaries: true,
                      addAutomaticKeepAlives: false,
                    ),
                  ),
                ),
            ],
          ),

          // Docked Bottom Action Bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(20, 14, 20, bottomPadding + 14),
              decoration: BoxDecoration(
                color: t.bg.withValues(alpha: 0.92),
                border: Border(
                  top: BorderSide(color: t.hairline, width: 1),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Dynamic Counter Text
                  Text(
                    canContinue
                        ? 'Great choice! $count artists selected'
                        : 'Select at least $_minRequired artists ($count selected)',
                    style: TextStyle(
                      fontFamily: 'PlusJakartaSans',
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: canContinue ? t.ink : t.inkMuted,
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Continue Button
                  TactileKeycap(
                    height: 48,
                    width: double.infinity,
                    accent: canContinue,
                    enabled: canContinue,
                    onPressed: canContinue ? _submit : null,
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            canContinue ? 'CONTINUE WITH $count ARTISTS' : 'SELECT 3 TO CONTINUE',
                            style: SwissType.label.copyWith(
                              color: canContinue ? t.accentInk : t.inkFaint,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.0,
                            ),
                          ),
                          if (canContinue) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.arrow_forward_rounded, size: 16, color: t.accentInk),
                          ],
                        ],
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
  }
}
