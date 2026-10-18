/// Build identity — the answer to "which APK am I actually running?".
///
/// On-device reports are the only ground truth for faults that cannot be
/// reproduced on a workstation. Every release stamps itself here, and the stamp
/// is printed in Settings ▸ ABOUT *and* at the top of `COPY REPORT`, so a bug
/// report always names the exact build it came from and "the fix is not in your
/// build" is ruled out in one glance.
///
/// Bump [kAppVersion]/[kAppBuild] whenever the version in `pubspec.yaml` moves,
/// and refresh [kBuildStamp]/[kBuildTag] whenever a release APK is produced.
const String kAppVersion = '1.0.4';
const int kAppBuild = 5;

/// Date (local) the release APK was produced.
const String kBuildStamp = '2026-10-18';

/// What is actually new in this build, in one word.
const String kBuildTag = 'RELEASE';

const String kBuildLabel =
    'MUSIFY $kAppVersion+$kAppBuild // $kBuildTag · $kBuildStamp';
