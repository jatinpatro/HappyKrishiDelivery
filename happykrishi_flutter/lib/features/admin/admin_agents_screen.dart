import '../../core/theme/app_theme.dart'; 
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';
import '../../core/utils/error_handler.dart';

final agentsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.adminAgents);
  return List<Map<String, dynamic>>.from(res.data['agents']);
});

class AdminAgentsScreen extends ConsumerWidget {
  const AdminAgentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agents = ref.watch(agentsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Delivery Agents'),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Home',
            onPressed: () => context.go('/admin/dashboard'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(agentsProvider),
          ),
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: 'Add Agent',
            onPressed: () => _showAddAgentDialog(context, ref),
          ),
        ],
      ),
      body: agents.when(
        data: (list) => list.isEmpty
            ? Center(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.delivery_dining, size: 72, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('No delivery agents yet',
                      style: TextStyle(color: Colors.grey, fontSize: 16)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.person_add),
                    label: const Text('Add First Agent'),
                    onPressed: () => _showAddAgentDialog(context, ref),
                  ),
                ]),
              )
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(agentsProvider),
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final a = list[i];
                    final isAvail = a['is_available'] == 1;
                    final isActive = a['is_active'] == 1;
                    final lastSeen = a['last_seen_at'] as String?;
                    final id = a['id'] as int;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isAvail && isActive
                              ? Colors.green
                              : isActive ? Colors.orange : Colors.grey,
                          child: Text(
                            (a['name'] as String).substring(0, 1).toUpperCase(),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(a['name'] as String,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('+91 ${a['phone']}',
                              style: const TextStyle(fontSize: 13)),
                          if (lastSeen != null)
                            Text('Last seen: ${lastSeen.substring(0, 16)}',
                                style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ]),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          // Availability badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: (isAvail && isActive)
                                  ? Colors.green.shade50
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: (isAvail && isActive) ? Colors.green : Colors.grey.shade300,
                              ),
                            ),
                            child: Text(
                              !isActive ? 'Inactive' : isAvail ? 'Available' : 'Busy',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: !isActive
                                    ? Colors.grey
                                    : isAvail ? Colors.green : Colors.orange,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Toggle active switch
                          Switch(
                            value: isActive,
                            activeTrackColor: AppColors.primary,
                            onChanged: (_) async {
                              final dio = ref.read(dioProvider);
                              await dio.put(Endpoints.adminAgentToggle(id));
                              ref.invalidate(agentsProvider);
                            },
                          ),
                          // Force logout
                          IconButton(
                            icon: const Icon(Icons.logout, size: 18),
                            tooltip: 'Force Logout',
                            color: Colors.red.shade400,
                            onPressed: () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Force Logout?'),
                                  content: Text('This will immediately log out ${a['name']}. They will need to log in again.'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                    ElevatedButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                                      child: const Text('Force Logout'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed != true) return;
                              try {
                                await ref.read(dioProvider).post(Endpoints.adminAgentForceLogout(id));
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    content: Text('${a['name']} logged out'),
                                    backgroundColor: Colors.orange,
                                  ));
                                }
                              } catch (_) {}
                            },
                          ),
                        ]),
                      ),
                    );
                  },
                ),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) { logError('admin-agents', e); return Center(child: Text(friendlyError(e))); },
      ),
    );
  }

  void _showAddAgentDialog(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    bool saving = false;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDs) => AlertDialog(
          title: const Text('Add Delivery Agent'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                  labelText: 'Full Name *',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              decoration: const InputDecoration(
                  labelText: 'Phone (10 digits) *',
                  prefixText: '+91 ',
                  counterText: '',
                  prefixIcon: Icon(Icons.phone),
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: passCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Password (optional, min 6)',
                  prefixIcon: Icon(Icons.lock_outline),
                  border: OutlineInputBorder()),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: saving ? null : () async {
                if (nameCtrl.text.trim().isEmpty || phoneCtrl.text.trim().length != 10) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Enter valid name and 10-digit phone')));
                  return;
                }
                setDs(() => saving = true);
                try {
                  final dio = ref.read(dioProvider);
                  await dio.post(Endpoints.adminAgents, data: {
                    'name': nameCtrl.text.trim(),
                    'phone': phoneCtrl.text.trim(),
                    if (passCtrl.text.length >= 6) 'password': passCtrl.text,
                  });
                  ref.invalidate(agentsProvider);
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Delivery agent added ✅'),
                      backgroundColor: AppColors.primary,
                    ));
                  }
                } on DioException catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(e.response?.data['error'] ?? 'Error')));
                  }
                } finally {
                  if (dialogCtx.mounted) setDs(() => saving = false);
                }
              },
              child: saving
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Add Agent'),
            ),
          ],
        ),
      ),
    );
  }
}
