// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Ukrainian (`uk`).
class AppLocalizationsUk extends AppLocalizations {
  AppLocalizationsUk([String locale = 'uk']) : super(locale);

  @override
  String get dropZoneTitle => 'Перетягніть сюди відео або папки';

  @override
  String get dropZoneHint => 'Оригінальні файли ніколи не змінюються.';

  @override
  String get addVideos => 'Додати відео';

  @override
  String get addFolder => 'Додати папку';

  @override
  String get yourVideos => 'Ваші відео';

  @override
  String get clearFinished => 'Прибрати готові';

  @override
  String get scenarioArchiveTitle => 'Для архіву';

  @override
  String get scenarioArchiveHint =>
      'Відео з камери займатимуть значно менше місця й виглядатимуть так само, як оригінал. Дати зйомки, дані камери, звук і кольори зберігаються.';

  @override
  String get scenarioResolveTitle => 'Монтувати в Resolve';

  @override
  String get scenarioResolveHint =>
      'Щоб відео відкривалися в DaVinci Resolve на Linux із зображенням і звуком.';

  @override
  String get archiveFormatTitle => 'Формат';

  @override
  String get archiveAv1 => 'Найменший файл';

  @override
  String get archiveAv1Hint =>
      'Відтворюється на комп’ютерах і новіших пристроях: iPhone 15 Pro і новіших, Mac з M3, телевізорах приблизно з 2020 року.';

  @override
  String get archiveHevc => 'Працює всюди';

  @override
  String get archiveHevcHint =>
      'Та сама якість, файл до третини більший. Відтворюється майже всюди, зокрема на старших iPhone, Mac і телевізорах.';

  @override
  String get archiveSpeedTitle => 'Швидкість';

  @override
  String get archiveCpu => 'Ретельно';

  @override
  String get archiveCpuHint =>
      'Кодує процесор: повільніше, але файл найменший.';

  @override
  String get archiveGpu => 'Швидко';

  @override
  String get archiveGpuHint =>
      'Кодує відеокарта: у кілька разів швидше. Складні кадри займають стільки ж, спокійні — до 2,5 раза більше.';

  @override
  String get presetResolveStudio => 'Resolve Studio';

  @override
  String get presetResolveStudioHint =>
      'Зазвичай треба виправити лише звук, це займає секунди.';

  @override
  String get presetResolveFree => 'Безкоштовний Resolve';

  @override
  String get presetResolveFreeHint =>
      'Зображення теж конвертується. Файли стають значно більшими.';

  @override
  String get sizeTitle => 'Розмір файлу';

  @override
  String get sizeSmallest => 'Найменший';

  @override
  String get sizeSmaller => 'Менший';

  @override
  String get sizeBalanced => 'Рекомендовано';

  @override
  String get sizeBest => 'Найкраща якість';

  @override
  String get convertVideoTitle => 'Конвертувати також зображення';

  @override
  String get convertVideoHint =>
      'Увімкніть, якщо відео гальмує або немає зображення. Потрібно без відеокарти NVIDIA.';

  @override
  String get saveTitle => 'Куди зберегти';

  @override
  String get saveNextToOriginals => 'Поруч з оригіналами, у папці «Converted»';

  @override
  String get saveChooseFolder => 'Змінити…';

  @override
  String get saveReset => 'Як за замовчуванням';

  @override
  String get pause => 'Пауза';

  @override
  String get resume => 'Продовжити';

  @override
  String get sampleFromStart => 'З початку';

  @override
  String get sampleFromMiddle => 'Із середини';

  @override
  String get remove => 'Прибрати';

  @override
  String get cancel => 'Скасувати';

  @override
  String get retry => 'Спробувати ще раз';

  @override
  String get showInFolder => 'Показати в папці';

  @override
  String get dragToReorder => 'Перетягніть, щоб змінити порядок';

  @override
  String get statusChecking => 'Перевірка…';

  @override
  String get statusReadyAsIs => 'Уже готове';

  @override
  String get statusQuickFix => 'Швидко, зображення не змінюється';

  @override
  String get statusFullConversion => 'Буде конвертовано';

  @override
  String get statusUnsupported => 'У цьому файлі немає зображення';

  @override
  String get statusUnreadable => 'Це не відеофайл';

  @override
  String get statusFailed => 'Не вдалося конвертувати';

  @override
  String get statusCancelled => 'Скасовано';

  @override
  String get statusStarting => 'Запуск…';

  @override
  String progressLeft(String time) {
    return 'залишилось $time';
  }

  @override
  String aboutSize(String size) {
    return 'приблизно $size';
  }

  @override
  String percentSmaller(int percent) {
    return 'на $percent% менше';
  }

  @override
  String percentLarger(int percent) {
    return 'на $percent% більше';
  }

  @override
  String videoCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count відео',
      many: '$count відео',
      few: '$count відео',
      one: '$count відео',
    );
    return '$_temp0';
  }

  @override
  String convertingCount(int current, int total) {
    return 'Конвертація $current з $total';
  }

  @override
  String get allDone => 'Усе готово';

  @override
  String savedSummary(String before, String after) {
    return '$before стало $after';
  }

  @override
  String durationSeconds(int seconds) {
    return '$seconds с';
  }

  @override
  String durationMinutes(int minutes) {
    return '$minutes хв';
  }

  @override
  String durationHours(int hours, int minutes) {
    return '$hours год $minutes хв';
  }

  @override
  String get unitGB => 'ГБ';

  @override
  String get unitMB => 'МБ';

  @override
  String get unitKB => 'КБ';

  @override
  String get playOriginal => 'Переглянути оригінал';

  @override
  String get close => 'Закрити';

  @override
  String get details => 'Подробиці';

  @override
  String get engineMissingTitle => 'Немає відеорушія';

  @override
  String get engineMissingBody =>
      'Для конвертації потрібен FFmpeg, але його не знайдено. Встановіть FFmpeg і запустіть програму знову.';

  @override
  String get startingUp => 'Підготовка…';

  @override
  String get quitTitle => 'Зупинити конвертацію і вийти?';

  @override
  String get quitBody =>
      'Відео, яке зараз конвертується, буде відкинуто. Готові відео залишаться.';

  @override
  String get quit => 'Вийти';

  @override
  String get keepConverting => 'Продовжити конвертацію';

  @override
  String get more => 'Більше';

  @override
  String get showCommand => 'Показати команду';

  @override
  String get commandTitle => 'Команда для цього відео';

  @override
  String get commandIntro =>
      'Саме це програма виконує для цього відео. Скопіюйте, щоб запустити самостійно в терміналі або змінити.';

  @override
  String get commandOneLine => 'Один рядок';

  @override
  String get commandExplained => 'З поясненнями';

  @override
  String get copy => 'Копіювати';

  @override
  String get copied => 'Скопійовано';

  @override
  String get moreOptions => 'Більше налаштувань…';

  @override
  String get optionCodecTitle => 'Формат для монтажу';

  @override
  String get cmdHideBanner => 'Не виводити інформацію про версію';

  @override
  String get cmdSeek => 'Почати з цього місця відео, у секундах';

  @override
  String get cmdInput => 'Відео, яке конвертується';

  @override
  String get cmdLength => 'Конвертувати лише стільки секунд';

  @override
  String get cmdKeepPicture => 'Взяти зображення з оригіналу';

  @override
  String get cmdKeepSound => 'Взяти всі звукові доріжки, якщо вони є';

  @override
  String get cmdNoPicture => 'Без зображення';

  @override
  String get cmdNoSound => 'Без звуку';

  @override
  String get cmdKeepMetadata => 'Зберегти дати, назви і таймкод';

  @override
  String get cmdDropMetadata => 'Прибрати дати, назви та інші відомості';

  @override
  String get cmdPictureCopy => 'Зображення: скопіювати як є, без втрати якості';

  @override
  String get cmdPictureEncoder => 'Зображення: перекодувати цим кодувальником';

  @override
  String get cmdSoundCopy => 'Звук: скопіювати як є';

  @override
  String get cmdSoundEncoder => 'Звук: перетворити в цей формат';

  @override
  String get cmdSpeedPreset =>
      'Старанність: повільніше дає менший файл за тієї ж якості';

  @override
  String get cmdQuality =>
      'Цільова якість (для більшості кодувальників менше число означає кращу якість і більший файл)';

  @override
  String get cmdProfile => 'Різновид формату';

  @override
  String get cmdEncoderTuning => 'Тонке налаштування кодувальника';

  @override
  String get cmdPixelFormat => 'Точність кольору зображення';

  @override
  String get cmdFilter => 'Обробка зображення';

  @override
  String get cmdSoundBitrate => 'Якість звуку, обсяг даних за секунду';

  @override
  String get cmdConstantFrameRate => 'Зробити частоту кадрів рівномірною';

  @override
  String get cmdFrameRate => 'Кадрів за секунду';

  @override
  String get cmdKeyframeInterval =>
      'Повний кадр щонайменше з такою частотою, для плавного перемотування';

  @override
  String get cmdPlayerTag =>
      'Позначка, за якою відео розпізнають програвачі Apple';

  @override
  String get cmdFastStart =>
      'Індекс на початку, щоб відтворення починалося під час завантаження';

  @override
  String get cmdFastStartKeepingTags =>
      'Індекс на початку, щоб відтворення починалося під час завантаження, і зберегти марку та модель камери';

  @override
  String get cmdLevelLimit =>
      'Не виходити за межі, які підтримує будь-який програвач відео такого розміру';

  @override
  String get cmdDropTag =>
      'Не переносити позначку типу файлу оригіналу: новому файлу вона не підходить';

  @override
  String get cmdContainer => 'Тип файлу результату';

  @override
  String get cmdOutput => 'Куди записується результат';

  @override
  String get scenarioShareTitle => 'Надіслати на телефон';

  @override
  String get scenarioShareHint =>
      'Маленький файл, що відтворюється на будь-якому телефоні, у Telegram та інших месенджерах. У Telegram надсилайте як файл, щоб зберегти цю якість.';

  @override
  String get scenarioAudioTitle => 'Дістати звук';

  @override
  String get scenarioAudioHint => 'Зберігає звук із відео окремим файлом.';

  @override
  String get scenarioPrivacyTitle => 'Прибрати особисті дані';

  @override
  String get scenarioPrivacyHint =>
      'Прибирає приховані позначки про місце, дату, камеру й автора перед тим, як ділитися відео. Те, що видно і чутно, не змінюється.';

  @override
  String get scenarioRemuxTitle => 'Змінити тип файлу';

  @override
  String get scenarioRemuxHint =>
      'За секунди перекладає відео в інший тип файлу, не змінюючи якості зображення.';

  @override
  String get optionSizeTitle => 'Розмір';

  @override
  String get shareSmall => 'Менший';

  @override
  String get shareStandard => 'Стандартний';

  @override
  String get optionFormatTitle => 'Тип файлу';

  @override
  String get formatOriginal => 'Як є';

  @override
  String get optionModeTitle => 'Наскільки ретельно';

  @override
  String get modeQuick => 'Швидко';

  @override
  String get modeThorough => 'Ретельно';

  @override
  String get modeThoroughHint =>
      'Ретельний режим заново створює зображення і звук. Це значно довше, але найнадійніше.';

  @override
  String get statusNoSound => 'У цьому файлі немає звуку';

  @override
  String get statusCannotHold => 'Цей тип файлу не може містити таке відео';

  @override
  String get estimating => 'оцінюємо розмір…';

  @override
  String takesAbout(String time) {
    return 'триватиме приблизно $time';
  }

  @override
  String get languageSystem => 'Як на комп’ютері';

  @override
  String get lookTitle => 'Вигляд';

  @override
  String get lookCozy => 'Затишний';

  @override
  String get lookPro => 'Професійний';

  @override
  String get techPictureCopied => 'зображення без змін';

  @override
  String get techSoundCopied => 'звук без змін';

  @override
  String get techNoSound => 'без звуку';

  @override
  String get techNoReencode => 'без перекодування';

  @override
  String techUpTo(String lines) {
    return 'до $lines';
  }

  @override
  String inQueueCount(int count) {
    return 'у черзі: $count';
  }

  @override
  String doneCount(int count) {
    return 'готово: $count';
  }

  @override
  String get videoDetails => 'Відомості про відео';

  @override
  String recipeTitleSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Що зробити з $count вибраними відео',
      many: 'Що зробити з $count вибраними відео',
      few: 'Що зробити з $count вибраними відео',
      one: 'Що зробити з $count вибраним відео',
    );
    return '$_temp0';
  }

  @override
  String get recipeTitleNone => 'Що зробити';

  @override
  String get selectVideosHint =>
      'Виберіть відео ліворуч, щоб вирішити, що з ними зробити.';

  @override
  String get convertTitle => 'Обсяг';

  @override
  String get convertWhole => 'Усе відео';

  @override
  String get convertSample => 'Зразок 10 секунд';

  @override
  String get addToQueue => 'Додати в чергу';

  @override
  String addAllToQueue(int count) {
    return 'Додати всі ($count)';
  }

  @override
  String get alreadyQueued => 'Уже в черзі';

  @override
  String samplesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count зразка по 10 секунд',
      many: '$count зразків по 10 секунд',
      few: '$count зразки по 10 секунд',
      one: '$count зразок по 10 секунд',
    );
    return '$_temp0';
  }

  @override
  String get queueTitle => 'Черга';

  @override
  String get queueEmpty =>
      'Виберіть відео і що з ними зробити, потім натисніть «Додати в чергу». Конвертація почнеться сама.';

  @override
  String get queuePaused => 'Призупинено';

  @override
  String get jobWaiting => 'Очікує';

  @override
  String pausedAt(int percent) {
    return 'Призупинено на $percent%';
  }

  @override
  String get jobSkipped => 'Нічого робити: уже як треба';

  @override
  String get sampleChip => 'Зразок 10 с';

  @override
  String sampleResult(String size, String fullSize, String time) {
    return 'Зразок $size · усе відео приблизно $fullSize, приблизно $time';
  }

  @override
  String tookTime(String time) {
    return 'тривало $time';
  }

  @override
  String get play => 'Відтворити';

  @override
  String get convertWholeVideo => 'Конвертувати все відео';

  @override
  String get originalDetails => 'Відомості про оригінал';

  @override
  String get resultDetails => 'Відомості про результат';

  @override
  String get useSettings => 'Використати ці налаштування';

  @override
  String get removeFromList => 'Прибрати зі списку';

  @override
  String get detailsViewEncoding => 'Кодування';

  @override
  String get detailsViewMetadata => 'Усі метадані';

  @override
  String get detailsViewReport => 'Повний звіт';

  @override
  String get noTags => 'Немає тегів';

  @override
  String get groupFile => 'Файл';

  @override
  String groupVideo(int number) {
    return 'Відеодоріжка $number';
  }

  @override
  String groupAudio(int number) {
    return 'Аудіодоріжка $number';
  }

  @override
  String groupSubtitle(int number) {
    return 'Субтитри $number';
  }

  @override
  String get groupTimecode => 'Таймкод';

  @override
  String groupData(int number) {
    return 'Доріжка даних $number';
  }

  @override
  String groupAttachment(int number) {
    return 'Вкладення $number';
  }

  @override
  String get groupChapters => 'Розділи';

  @override
  String groupChapter(int number) {
    return 'Розділ $number';
  }

  @override
  String get fieldContainer => 'Контейнер';

  @override
  String get fieldSize => 'Розмір';

  @override
  String get fieldDuration => 'Тривалість';

  @override
  String get fieldBitrate => 'Бітрейт';

  @override
  String get fieldTracks => 'Доріжок';

  @override
  String get fieldCodec => 'Кодек';

  @override
  String get fieldResolution => 'Роздільна здатність';

  @override
  String get fieldAspectRatio => 'Співвідношення сторін';

  @override
  String get fieldFrameRate => 'Частота кадрів';

  @override
  String get fieldBitDepth => 'Глибина кольору';

  @override
  String get fieldChroma => 'Субдискретизація кольору';

  @override
  String get fieldPixelFormat => 'Формат пікселів';

  @override
  String get fieldColorPrimaries => 'Основні кольори';

  @override
  String get fieldColorTransfer => 'Передавальна функція';

  @override
  String get fieldColorMatrix => 'Матриця';

  @override
  String get fieldColorRange => 'Діапазон';

  @override
  String get fieldHdr => 'HDR';

  @override
  String get fieldMasteringDisplay => 'Дисплей мастерингу';

  @override
  String get fieldLightLevel => 'Рівень світла';

  @override
  String get fieldScanType => 'Розгортка';

  @override
  String get fieldRotation => 'Поворот';

  @override
  String get fieldFrames => 'Кадрів';

  @override
  String get fieldChannels => 'Канали';

  @override
  String get fieldSampleRate => 'Частота дискретизації';

  @override
  String get fieldSampleFormat => 'Формат відліків';

  @override
  String get fieldLanguage => 'Мова';

  @override
  String get fieldTitle => 'Назва';

  @override
  String get fieldDefaultTrack => 'Типова доріжка';

  @override
  String get fieldTimecode => 'Таймкод';

  @override
  String get fieldFileName => 'Ім’я файлу';

  @override
  String get fieldChapter => 'Розділ';

  @override
  String get noteVariable => 'змінна';

  @override
  String get noteProgressive => 'прогресивна';

  @override
  String get noteInterlaced => 'черезрядкова';

  @override
  String get noteNotStated => 'не вказано';

  @override
  String get noteYes => 'так';

  @override
  String get noteNo => 'ні';

  @override
  String get appTitle => 'VidCtrl';

  @override
  String get noteVariableFrameRate =>
      'Нерівномірну частоту кадрів буде виправлено.';

  @override
  String get noteHevc422 =>
      'Цей формат запису відтворюється в Resolve лише з новою відеокартою NVIDIA.';

  @override
  String get noteExperimentalAv1 => 'Найменші файли важче плавно монтувати.';

  @override
  String get noteHdrToneMapped =>
      'Дуже яскраві кольори буде пристосовано, щоб відео гарно виглядало на будь-якому екрані.';

  @override
  String get noteHdrNotConverted =>
      'У цьому відео надяскраві кольори, які на телефоні можуть виглядати блідо.';

  @override
  String get noteAudioConvertedToFit =>
      'Звук буде перетворено, щоб він підходив до цього типу файлу.';

  @override
  String get selectAll => 'Вибрати всі';

  @override
  String selectedCount(int count) {
    return 'вибрано: $count';
  }

  @override
  String get convertSampleShort => 'Зразок';

  @override
  String get sampleFirst => 'перші 10 с';

  @override
  String get sampleMiddle => '10 с із середини';

  @override
  String get personalTag => 'Особисті дані: хто, де, коли або чим зняв відео';
}
