import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/people_bloc.dart';

class PeoplePage extends StatelessWidget {
  const PeoplePage({super.key});
  @override
  Widget build(BuildContext context) =>
      BlocBuilder<PeopleBloc, PeopleState>(builder: (context, state) {
        if (state.status == PeopleStatus.loading)
          return const Center(child: CircularProgressIndicator());
        if (state.status == PeopleStatus.failure)
          return Center(child: Text(state.message ?? 'Could not load people.'));
        if (state.people.isEmpty)
          return const Center(child: Text('No community members to show yet.'));
        return ListView(padding: const EdgeInsets.all(16), children: [
          Text('People',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Get to know your company community.'),
          const SizedBox(height: 18),
          ...state.people.map((person) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                    child: Text(person.name.isEmpty
                        ? '?'
                        : person.name[0].toUpperCase())),
                title: Text(person.name),
                subtitle: Text(
                    person.role.isNotEmpty ? person.role : 'Community member'),
                trailing: const Icon(Icons.chevron_right),
              ))),
        ]);
      });
}
