import '../../core/di/injection_container.dart';
import '../feed/domain/repositories/i_community_repository.dart';
import 'domain/usecases/load_people_usecase.dart';
import 'presentation/bloc/people_bloc.dart';

void registerPeopleFeature() {
  sl.registerLazySingleton(() => LoadPeopleUseCase(sl<ICommunityRepository>()));

  sl.registerFactory<PeopleBloc>(() => PeopleBloc(sl<LoadPeopleUseCase>()));
}
