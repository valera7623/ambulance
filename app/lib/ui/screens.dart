import 'package:flutter/material.dart';

import '../controller.dart';
import '../data/card_format.dart';
import '../data/models.dart';
import '../data/sections.dart';
import '../scope.dart';
import '../share_text.dart';
import 'card_body.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ContentController? _controller;
  List<Department> _departments = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = ContentScope.of(context);
    if (!identical(next, _controller)) {
      _controller?.removeListener(_reload);
      _controller = next;
      _controller!.addListener(_reload);
      _reload();
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final departments = await _controller!.repository.departments();
    final visible = <Department>[];
    for (final department in departments) {
      final diagnoses =
          await _controller!.repository.diagnosesInDepartment(department.id);
      if (diagnoses.isNotEmpty) visible.add(department);
    }
    if (!mounted) return;
    setState(() => _departments = visible);
  }

  @override
  Widget build(BuildContext context) {
    final controller = ContentScope.of(context);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: const Text(
          'Клинические рекомендации для СМП',
          maxLines: 2,
        ),
        actions: [
          IconButton(
            tooltip: 'Поиск',
            onPressed: () => pushPath(context, '/search'),
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: 'Избранное',
            onPressed: () => pushPath(context, '/favorites'),
            icon: const Icon(Icons.star_outline),
          ),
          IconButton(
            tooltip: 'Настройки',
            onPressed: () => pushPath(context, '/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: ListTile(
              dense: true,
              title: Text(controller.statusLine),
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: _departments.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final department = _departments[index];
                return ListTile(
                  key: Key('department-${department.slug}'),
                  title: Text(department.title),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    if (department.slug == continuousSectionSlug) {
                      pushPath(context, '/section/${department.slug}/document');
                    } else {
                      pushPath(context, '/section/${department.slug}');
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class DepartmentScreen extends StatefulWidget {
  const DepartmentScreen({required this.slug, super.key});

  final String slug;

  @override
  State<DepartmentScreen> createState() => _DepartmentScreenState();
}

class _DepartmentScreenState extends State<DepartmentScreen> {
  ContentController? _controller;
  Department? _department;
  List<Diagnosis> _diagnoses = [];
  bool _missing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = ContentScope.of(context);
    if (!identical(next, _controller)) {
      _controller?.removeListener(_reload);
      _controller = next;
      _controller!.addListener(_reload);
      _reload();
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final department = await _controller!.repository.departmentBySlug(widget.slug);
    if (department == null) {
      if (!mounted) return;
      setState(() => _missing = true);
      return;
    }
    final diagnoses =
        await _controller!.repository.diagnosesInDepartment(department.id);
    if (!mounted) return;
    setState(() {
      _department = department;
      _diagnoses = diagnoses;
      _missing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = _department?.title ?? 'Раздел';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _missing
          ? const Center(child: Text('Раздел не найден'))
          : _diagnoses.isEmpty
              ? const Center(child: Text('В этом разделе пока нет протоколов'))
              : ListView.separated(
                  itemCount: _diagnoses.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final diagnosis = _diagnoses[index];
                    final code = diagnosis.displayCode;
                    return ListTile(
                      key: Key('dx-${diagnosis.stableKey}'),
                      title: Text(
                        code == null || code.isEmpty
                            ? diagnosis.title
                            : '$code  ${diagnosis.title}',
                      ),
                      subtitle: diagnosis.isEmergency
                          ? const Text('Неотложное')
                          : null,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(diagnosis),
                    );
                  },
                ),
    );
  }

  Future<void> _open(Diagnosis diagnosis) async {
    final subs = await _controller!.repository.subconditionsOf(diagnosis.id);
    if (!mounted) return;
    if (subs.isEmpty) {
      pushPath(context, '/dx/${diagnosis.stableKey}');
    } else {
      pushPath(context, '/dx/${diagnosis.stableKey}/subs');
    }
  }
}

class SubconditionScreen extends StatefulWidget {
  const SubconditionScreen({required this.stableKey, super.key});

  final String stableKey;

  @override
  State<SubconditionScreen> createState() => _SubconditionScreenState();
}

class _SubconditionScreenState extends State<SubconditionScreen> {
  ContentController? _controller;
  Diagnosis? _diagnosis;
  List<Subcondition> _subs = [];
  CardContent? _base;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = ContentScope.of(context);
    if (!identical(next, _controller)) {
      _controller?.removeListener(_reload);
      _controller = next;
      _controller!.addListener(_reload);
      _reload();
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final diagnosis = await _controller!.repository.diagnosisByKey(widget.stableKey);
    if (diagnosis == null) {
      if (!mounted) return;
      setState(() => _diagnosis = null);
      return;
    }
    final subs = await _controller!.repository.subconditionsOf(diagnosis.id);
    final base = await _controller!.repository.cardFor(widget.stableKey);
    if (!mounted) return;
    setState(() {
      _diagnosis = diagnosis;
      _subs = subs;
      _base = base;
    });
  }

  @override
  Widget build(BuildContext context) {
    final diagnosis = _diagnosis;
    if (diagnosis == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Диагноз')),
        body: const Center(child: Text('Карточка не найдена. Справочник мог обновиться.')),
      );
    }
    final prompt = diagnosis.branchPrompt?.trim();
    return Scaffold(
      appBar: AppBar(title: Text(diagnosis.title)),
      body: ListView(
        children: [
          if (prompt != null && prompt.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(prompt, style: Theme.of(context).textTheme.titleMedium),
            ),
          if (_base != null && _base!.care.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(height: 220, child: CardBody(card: _base!)),
            ),
          for (final sub in _subs)
            ListTile(
              key: Key('sub-${sub.id}'),
              title: Text('${sub.codeLabel}  ${sub.title}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => pushPath(context, '/dx/${widget.stableKey}/sub/${sub.id}'),
            ),
        ],
      ),
    );
  }
}

class DiagnosisCardScreen extends StatefulWidget {
  const DiagnosisCardScreen({required this.stableKey, this.subId, super.key});

  final String stableKey;
  final int? subId;

  @override
  State<DiagnosisCardScreen> createState() => _DiagnosisCardScreenState();
}

class _DiagnosisCardScreenState extends State<DiagnosisCardScreen> {
  ContentController? _controller;
  CardContent? _card;
  bool _favorite = false;
  bool _missing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = ContentScope.of(context);
    if (!identical(next, _controller)) {
      _controller?.removeListener(_reload);
      _controller = next;
      _controller!.addListener(_reload);
      _reload();
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final card = await _controller!.repository.cardFor(widget.stableKey, subId: widget.subId);
    final favorite = await _controller!.repository.isFavorite(widget.stableKey);
    if (!mounted) return;
    setState(() {
      _card = card;
      _favorite = favorite;
      _missing = card == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final card = _card;
    return Scaffold(
      appBar: AppBar(
        title: Text(card?.title ?? 'Карточка'),
        actions: [
          if (card != null)
            IconButton(
              key: const Key('favorite-toggle'),
              tooltip: _favorite ? 'Убрать из избранного' : 'В избранное',
              onPressed: () async {
                final now = await _controller!.repository.toggleFavorite(card.stableKey);
                if (!mounted) return;
                setState(() => _favorite = now);
              },
              icon: Icon(_favorite ? Icons.star : Icons.star_outline),
            ),
          if (card != null)
            IconButton(
              tooltip: 'Поделиться текстом',
              onPressed: () => sharePlainText(card.plainText),
              icon: const Icon(Icons.ios_share),
            ),
        ],
      ),
      body: _missing
          ? const Center(child: Text('Карточка не найдена. Справочник мог обновиться.'))
          : card == null
              ? const Center(child: CircularProgressIndicator())
              : CardBody(card: card),
    );
  }
}

class ContinuousScreen extends StatefulWidget {
  const ContinuousScreen({required this.slug, super.key});

  final String slug;

  @override
  State<ContinuousScreen> createState() => _ContinuousScreenState();
}

class _ContinuousScreenState extends State<ContinuousScreen> {
  ContentController? _controller;
  Department? _department;
  List<CardContent> _cards = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = ContentScope.of(context);
    if (!identical(next, _controller)) {
      _controller?.removeListener(_reload);
      _controller = next;
      _controller!.addListener(_reload);
      _reload();
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final department = await _controller!.repository.departmentBySlug(widget.slug);
    final cards = await _controller!.repository.continuousCards(widget.slug);
    if (!mounted) return;
    setState(() {
      _department = department;
      _cards = cards;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_department?.title ?? 'Раздел')),
      body: _cards.isEmpty
          ? const Center(child: Text('В этом разделе пока нет протоколов'))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              itemCount: _cards.length + 1,
              itemBuilder: (context, index) {
                if (index == _cards.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      kDisclaimer,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  );
                }
                final card = _cards[index];
                return Padding(
                  padding: EdgeInsets.only(top: index == 0 ? 0 : 20),
                  child: ContinuousSection(card: card),
                );
              },
            ),
    );
  }
}

class ContinuousSection extends StatelessWidget {
  const ContinuousSection({required this.card, super.key});

  final CardContent card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blocks = <Widget>[
      Text(
        card.code == null ? card.title : '${card.title}  ${card.code}',
        style: theme.textTheme.titleLarge,
      ),
    ];
    if (card.conditionBody != null) {
      blocks
        ..add(const SizedBox(height: 8))
        ..add(Text(card.conditionBody!, style: theme.textTheme.bodyLarge));
    }
    if (card.care.trim().isNotEmpty) {
      blocks
        ..add(const SizedBox(height: 12))
        ..add(
          Text(
            card.careLabel,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        )
        ..add(const SizedBox(height: 4))
        ..add(_ContinuousProse(text: card.care));
    }
    if (card.tactic.trim().isNotEmpty) {
      blocks
        ..add(const SizedBox(height: 12))
        ..add(
          Text(
            card.tacticLabel,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        )
        ..add(const SizedBox(height: 4))
        ..add(_ContinuousProse(text: card.tactic));
    }
    blocks
      ..add(const SizedBox(height: 16))
      ..add(const Divider(thickness: 1));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }
}

class _ContinuousProse extends StatelessWidget {
  const _ContinuousProse({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in text.split('\n'))
          if (line.trim().isEmpty)
            const SizedBox(height: 8)
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                line.trim(),
                style: emphasizeLine(line)
                    ? style?.copyWith(fontWeight: FontWeight.w700)
                    : style,
              ),
            ),
      ],
    );
  }
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _query = TextEditingController();
  List<Diagnosis> _results = [];

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search(String value) async {
    final rows = await ContentScope.of(context).repository.search(value);
    if (!mounted) return;
    setState(() => _results = rows);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Поиск')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              key: const Key('search-field'),
              controller: _query,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Диагноз или препарат',
                border: OutlineInputBorder(),
              ),
              onChanged: _search,
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: _results.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final diagnosis = _results[index];
                final code = diagnosis.displayCode;
                return ListTile(
                  title: Text(
                    code == null || code.isEmpty
                        ? diagnosis.title
                        : '$code  ${diagnosis.title}',
                  ),
                  onTap: () async {
                    final subs = await ContentScope.of(context)
                        .repository
                        .subconditionsOf(diagnosis.id);
                    if (!context.mounted) return;
                    if (subs.isEmpty) {
                      pushPath(context, '/dx/${diagnosis.stableKey}');
                    } else {
                      pushPath(context, '/dx/${diagnosis.stableKey}/subs');
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  ContentController? _controller;
  List<Diagnosis> _rows = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = ContentScope.of(context);
    if (!identical(next, _controller)) {
      _controller?.removeListener(_reload);
      _controller = next;
      _controller!.addListener(_reload);
      _reload();
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final rows = await _controller!.repository.favorites();
    if (!mounted) return;
    setState(() => _rows = rows);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Избранное')),
      body: _rows.isEmpty
          ? const Center(child: Text('Пока ничего не сохранено'))
          : ListView.separated(
              itemCount: _rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final diagnosis = _rows[index];
                return ListTile(
                  title: Text(diagnosis.title),
                  trailing: IconButton(
                    tooltip: 'Убрать',
                    onPressed: () async {
                      await _controller!.repository.toggleFavorite(diagnosis.stableKey);
                      await _reload();
                    },
                    icon: const Icon(Icons.delete_outline),
                  ),
                  onTap: () => pushPath(context, '/dx/${diagnosis.stableKey}'),
                );
              },
            ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Вход')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Мастер-пароль нужен только для обновления с сервера станции. Справочник на телефоне открывается без него.',
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('password-field'),
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Мастер-пароль',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? 'Проверка…' : 'Войти'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await ContentScope.of(context).login(_password.text);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
    });
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  TextEditingController? _base;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _base ??= TextEditingController(text: ContentScope.of(context).apiBase);
  }

  @override
  void dispose() {
    _base?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ContentScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(controller.statusLine),
          const SizedBox(height: 8),
          Text('Отпечаток: ${controller.fingerprint.isEmpty ? '—' : controller.fingerprint}'),
          const SizedBox(height: 16),
          TextField(
            controller: _base!,
            decoration: const InputDecoration(
              labelText: 'Адрес сервера протоколов',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) => controller.setApiBase(value),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: controller.syncing
                ? null
                : () async {
                    await controller.setApiBase(_base!.text);
                    await controller.syncNow();
                  },
            child: const Text('Обновить протоколы'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => controller.loggedIn
                ? controller.logout()
                : pushPath(context, '/login'),
            child: Text(controller.loggedIn ? 'Выйти' : 'Войти'),
          ),
          const SizedBox(height: 24),
          Text('Размер текста', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<double>(
            segments: const [
              ButtonSegment(value: 1.0, label: Text('Обычный')),
              ButtonSegment(value: 1.15, label: Text('Крупнее')),
              ButtonSegment(value: 1.3, label: Text('Крупный')),
            ],
            selected: {controller.textScale},
            onSelectionChanged: (value) => controller.setTextScale(value.first),
          ),
          const SizedBox(height: 24),
          Text('Тема', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('Система')),
              ButtonSegment(value: ThemeMode.light, label: Text('Светлая')),
              ButtonSegment(value: ThemeMode.dark, label: Text('Тёмная')),
            ],
            selected: {controller.themeMode},
            onSelectionChanged: (value) => controller.setThemeMode(value.first),
          ),
          const SizedBox(height: 24),
          Text(kDisclaimer),
        ],
      ),
    );
  }
}

void pushPath(BuildContext context, String path) {
  final segments = Uri.parse(path).pathSegments;
  final Widget page;
  if (path == '/search') {
    page = const SearchScreen();
  } else if (path == '/favorites') {
    page = const FavoritesScreen();
  } else if (path == '/settings') {
    page = const SettingsScreen();
  } else if (path == '/login') {
    page = const LoginScreen();
  } else if (segments.length == 3 &&
      segments[0] == 'section' &&
      segments[2] == 'document') {
    page = ContinuousScreen(slug: segments[1]);
  } else if (segments.length == 2 && segments[0] == 'section') {
    page = DepartmentScreen(slug: segments[1]);
  } else if (segments.length == 3 && segments[0] == 'dx' && segments[2] == 'subs') {
    page = SubconditionScreen(stableKey: segments[1]);
  } else if (segments.length == 4 && segments[0] == 'dx' && segments[2] == 'sub') {
    page = DiagnosisCardScreen(
      stableKey: segments[1],
      subId: int.tryParse(segments[3]),
    );
  } else if (segments.length == 2 && segments[0] == 'dx') {
    page = DiagnosisCardScreen(stableKey: segments[1]);
  } else {
    throw ArgumentError('Unknown path $path');
  }
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
}
