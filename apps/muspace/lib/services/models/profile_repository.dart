import '../../workspace/workspace_repository.dart';
import 'model_gateway.dart';

class ProfileRepository {
  ProfileRepository(this.workspaces);
  final WorkspaceRepository workspaces;
  List<ModelProfile> all() {
    final value = workspaces.setting('modelProfiles');
    if (value is! List) return [];
    return [
      for (final item in value)
        ModelProfile(
          id: item['id'] as String,
          endpoint: Uri.parse(item['endpoint'] as String),
          location: ModelLocation.values.byName(item['location'] as String),
          modelId: item['modelId'] as String,
          endpointIdentity: item['endpointIdentity'] as String,
          credentialRef: item['credentialRef'] as String?,
          cloudProxy: item['cloudProxy'] as bool? ?? false,
        ),
    ];
  }

  Future<void> save(ModelProfile profile) async {
    final profiles = all();
    profiles.removeWhere((p) => p.id == profile.id);
    profiles.add(profile);
    await workspaces.setSetting(
      'modelProfiles',
      profiles.map((p) => p.toJson()).toList(),
    );
  }
}
