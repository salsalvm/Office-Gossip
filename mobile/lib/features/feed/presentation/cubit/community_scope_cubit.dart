import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/community_scope.dart';

/// App-wide selected community, shared by the Home and Trending tabs.
class CommunityScopeCubit extends Cubit<CommunityScope> {
  CommunityScopeCubit() : super(CommunityScope.global);

  void select(CommunityScope scope) => emit(scope);
}
