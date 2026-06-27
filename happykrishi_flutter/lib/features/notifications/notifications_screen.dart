import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';
import '../../core/models/models.dart';
import '../../core/utils/error_handler.dart';

final notificationsProvider = FutureProvider.autoDispose<List<AppNotification>>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.notifications);
  return (res.data['notifications'] as List).map((e) => AppNotification.fromJson(e)).toList();
});

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifs = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Home',
            onPressed: () => context.go('/home'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(notificationsProvider),
          ),
        ],
      ),
      body: notifs.when(
        data: (list) => list.isEmpty
            ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.notifications_none, size: 72, color: Colors.grey),
                SizedBox(height: 12),
                Text('No notifications yet', style: TextStyle(color: Colors.grey)),
              ]))
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(notificationsProvider),
                child: ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final n = list[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: n.isRead ? Colors.grey.shade200 : const Color(0xFFE8F5E9),
                        child: Icon(Icons.notifications, color: n.isRead ? Colors.grey : const Color(0xFF2E7D32)),
                      ),
                      title: Text(n.title, style: TextStyle(fontWeight: n.isRead ? FontWeight.normal : FontWeight.bold)),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(n.body),
                        Text(n.createdAt.substring(0, 16), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ]),
                      onTap: () async {
                        if (!n.isRead) {
                          final dio = ref.read(dioProvider);
                          await dio.put('${Endpoints.notifications}/${n.id}/read');
                          ref.invalidate(notificationsProvider);
                        }
                      },
                    );
                  },
                ),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) {
          logError('notifications', e);
          return Center(child: Text(friendlyError(e)));
        },
      ),
    );
  }
}
