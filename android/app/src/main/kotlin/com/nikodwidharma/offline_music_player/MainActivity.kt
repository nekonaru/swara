package com.nikodwidharma.offline_music_player

import com.ryanheise.audioservice.AudioServiceFragmentActivity

// AudioServiceFragmentActivity is the stable variant of the audio_service
// activity: the plain AudioServiceActivity crashed right after the
// notification was created on some devices (especially custom ROMs and
// skins such as XOS, MIUI). It extends FlutterFragmentActivity and needs a
// Theme.AppCompat descendant theme (see values/styles.xml).
class MainActivity : AudioServiceFragmentActivity()
