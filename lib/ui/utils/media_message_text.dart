import 'package:intl/intl.dart';

/// 跟随聊天组件语言，供没有 BuildContext 的摘要和时间格式化共用。
String mediaMessageText(String key, {String? locale}) {
  final language = (locale ?? Intl.getCurrentLocale()).replaceAll('-', '_');
  final code = language.startsWith('zh')
      ? (language.contains('TW') || language.contains('Hant')
          ? 'zh_TW'
          : 'zh_CN')
      : language.split('_').first;
  return (_mediaTexts[key]?[code] ?? _mediaTexts[key]?['en'] ?? key);
}

const _mediaTexts = {
  'downloadFailed': {
    'zh_CN': '下载失败，点击重试',
    'zh_TW': '下載失敗，點擊重試',
    'en': 'Download failed. Tap to retry.',
    'ja': 'ダウンロードできません。タップして再試行',
    'ms': 'Muat turun gagal. Ketik untuk cuba lagi.',
    'jv': 'Undhuhan gagal. Tutul kanggo nyoba maneh.',
    'id': 'Unduhan gagal. Ketuk untuk mencoba lagi.'
  },
  'justNow': {
    'zh_CN': '刚刚',
    'zh_TW': '剛剛',
    'en': 'Just now',
    'ja': 'たった今',
    'ms': 'Baru sahaja',
    'jv': 'Lagi wae',
    'id': 'Baru saja'
  },
  'unplayable': {
    'zh_CN': '无法播放此视频，请从文件入口发送',
    'zh_TW': '無法播放此影片，請從檔案入口傳送',
    'en': 'Unable to play this video. Send it from Files.',
    'ja': '再生できません。ファイルから送信してください',
    'ms': 'Video tidak dapat dimainkan. Hantar melalui Fail.',
    'jv': 'Video ora bisa diputer. Kirim liwat Berkas.',
    'id': 'Video tidak dapat diputar. Kirim melalui File.'
  },
  'failed': {
    'zh_CN': '发送失败，请重试',
    'zh_TW': '傳送失敗，請重試',
    'en': 'Sending failed. Try again.',
    'ja': '送信できませんでした。再試行してください',
    'ms': 'Gagal menghantar. Cuba lagi.',
    'jv': 'Gagal ngirim. Coba maneh.',
    'id': 'Gagal mengirim. Coba lagi.'
  },
  'playFailed': {
    'zh_CN': '视频播放失败',
    'zh_TW': '影片播放失敗',
    'en': 'Video playback failed',
    'ja': '動画を再生できません',
    'ms': 'Video gagal dimainkan',
    'jv': 'Video gagal diputer',
    'id': 'Video gagal diputar'
  },
  'retry': {
    'zh_CN': '重试',
    'zh_TW': '重試',
    'en': 'Retry',
    'ja': '再試行',
    'ms': 'Cuba lagi',
    'jv': 'Coba maneh',
    'id': 'Coba lagi'
  },
  'original': {
    'zh_CN': '下载原文件',
    'zh_TW': '下載原始檔案',
    'en': 'Download original',
    'ja': '元のファイルをダウンロード',
    'ms': 'Muat turun asal',
    'jv': 'Undhuh berkas asli',
    'id': 'Unduh file asli'
  },
};
