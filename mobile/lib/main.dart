import 'package:flutter/material.dart';

void main() => runApp(const OfficeGossipApp());

class OfficeGossipApp extends StatefulWidget {
  const OfficeGossipApp({super.key});
  @override State<OfficeGossipApp> createState() => _OfficeGossipAppState();
}

class _OfficeGossipAppState extends State<OfficeGossipApp> {
  ThemeMode _themeMode = ThemeMode.system;
  @override Widget build(BuildContext context) => MaterialApp(
    title: 'OfficeGossip', debugShowCheckedModeBanner: false, themeMode: _themeMode,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7357E8), brightness: Brightness.light), useMaterial3: true),
    darkTheme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF9A84FF), brightness: Brightness.dark), useMaterial3: true),
    home: HomeShell(themeMode: _themeMode, onThemeChanged: (mode) => setState(() => _themeMode = mode)),
  );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.themeMode, required this.onThemeChanged});
  final ThemeMode themeMode; final ValueChanged<ThemeMode> onThemeChanged;
  @override State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final _titles = const ['Home', 'Trending', 'People', 'Profile'];
  @override Widget build(BuildContext context) {
    final pages = [const FeedPage(), const PlaceholderPage(title: 'Trending'), const PlaceholderPage(title: 'People'), ProfilePage(themeMode: widget.themeMode, onThemeChanged: widget.onThemeChanged)];
    return Scaffold(
      appBar: AppBar(title: const Text('👀 OfficeGossip'), actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_outlined), tooltip: 'Notifications')]),
      body: SafeArea(child: pages[_index]),
      floatingActionButton: _index == 0 ? FloatingActionButton.extended(onPressed: () => showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => const ComposeSheet()), icon: const Icon(Icons.add), label: const Text('Post')) : null,
      bottomNavigationBar: NavigationBar(selectedIndex: _index, onDestinationSelected: (i) => setState(() => _index = i), destinations: const [NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'), NavigationDestination(icon: Icon(Icons.local_fire_department_outlined), label: 'Trending'), NavigationDestination(icon: Icon(Icons.people_outline), label: 'People'), NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile')]),
    );
  }
}

class FeedPage extends StatelessWidget {
  const FeedPage({super.key});
  @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [Text('Good morning 👋', style: Theme.of(context).textTheme.headlineSmall), const SizedBox(height: 4), Text('The latest from your company community', style: Theme.of(context).textTheme.bodyMedium), const SizedBox(height: 20), Card(child: ListTile(leading: const CircleAvatar(child: Icon(Icons.visibility_off_outlined)), title: const Text('Anonymous · 2h'), subtitle: const Padding(padding: EdgeInsets.only(top: 10), child: Text('Team lunch moved to Friday 😄', style: TextStyle(fontSize: 16))), trailing: IconButton(onPressed: () {}, icon: const Icon(Icons.more_horiz)),)), const SizedBox(height: 8), const Card(child: Padding(padding: EdgeInsets.all(12), child: Row(children: [Icon(Icons.favorite_border), SizedBox(width: 8), Text('Like'), SizedBox(width: 24), Icon(Icons.chat_bubble_outline), SizedBox(width: 8), Text('Comment')]))), const SizedBox(height: 12), const Center(child: Text('Starter preview — feed will load from the API.'))]);
}

class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({super.key, required this.title}); final String title;
  @override Widget build(BuildContext context) => Center(child: Text('$title screen starter'));
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, required this.themeMode, required this.onThemeChanged}); final ThemeMode themeMode; final ValueChanged<ThemeMode> onThemeChanged;
  @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [const CircleAvatar(radius: 36, child: Icon(Icons.person, size: 36)), const SizedBox(height: 12), Text('Your profile', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 16), Card(child: Column(children: [ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Edit profile'), trailing: const Icon(Icons.chevron_right), onTap: () {}), const Divider(height: 1), ListTile(leading: const Icon(Icons.business_outlined), title: const Text('Company'), subtitle: const Text('Select or request a company'), trailing: const Icon(Icons.chevron_right), onTap: () {}), const Divider(height: 1), ListTile(leading: const Icon(Icons.notifications_outlined), title: const Text('Notifications'), trailing: const Icon(Icons.chevron_right), onTap: () {})])), const SizedBox(height: 12), Card(child: Padding(padding: const EdgeInsets.all(16), child: DropdownButtonFormField<ThemeMode>(initialValue: themeMode, decoration: const InputDecoration(labelText: 'Appearance', border: InputBorder.none), items: const [DropdownMenuItem(value: ThemeMode.system, child: Text('System default')), DropdownMenuItem(value: ThemeMode.light, child: Text('Light')), DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark'))], onChanged: (value) { if (value != null) onThemeChanged(value); }))) ]);
}

class ComposeSheet extends StatefulWidget { const ComposeSheet({super.key}); @override State<ComposeSheet> createState() => _ComposeSheetState(); }
class _ComposeSheetState extends State<ComposeSheet> { bool _anonymous = true;
  @override Widget build(BuildContext context) => Padding(padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [Text('Create a post', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 12), const TextField(maxLines: 5, maxLength: 500, decoration: InputDecoration(hintText: 'What’s happening at work? Add emojis 😄', border: OutlineInputBorder())), SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Post anonymously'), value: _anonymous, onChanged: (v) => setState(() => _anonymous = v)), FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Share post'))]));
}
