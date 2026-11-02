import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/app_theme.dart';
import '../data/database_helper.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

class ClientManagementScreen extends StatefulWidget {
  const ClientManagementScreen({super.key});

  @override
  State<ClientManagementScreen> createState() => _ClientManagementScreenState();
}

class _ClientManagementScreenState extends State<ClientManagementScreen> {
  final _searchController = TextEditingController();
  final _currencyFormat = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

  List<User> _users = [];
  Map<int, Map<String, dynamic>> _userStats = {};
  bool _isLoading = true;
  String _filter = 'all'; // 'all', 'active', 'inactive', 'admins'
  String _searchQuery = '';

  // Network metrics
  int _totalUsers = 0;
  int _activeClients = 0;
  int _inactiveClients = 0;
  double _totalNetworkSales = 0.0;

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadClients() async {
    setState(() => _isLoading = true);

    try {
      // 0. Ensure local default admin exists
      await DatabaseHelper.instance.ensureDefaultAdmin();

      // 1. Try fetching from online backend if available
      try {
        final onlineData = await ApiService.instance.getAdminClients();
        if (onlineData['clients'] != null && mounted) {
          final List clientsJson = onlineData['clients'];
          for (var item in clientsJson) {
            final username = item['username'];
            var localUser = await DatabaseHelper.instance.getUser(username);
            if (localUser != null) {
              final updated = localUser.copyWith(
                id: item['id'] ?? localUser.id,
                fullName: item['full_name'] ?? localUser.fullName,
                email: item['email'] ?? localUser.email,
                role: item['role'] ?? localUser.role,
                isActive: item['is_active'] ?? localUser.isActive,
              );
              await DatabaseHelper.instance.updateUser(updated);
            } else {
              final newUser = User(
                id: item['id'],
                username: item['username'],
                password: '',
                fullName: item['full_name'] ?? item['username'],
                email: item['email'],
                role: item['role'] ?? 'client',
                isActive: item['is_active'] ?? true,
                createdAt: item['created_at'] != null
                    ? DateTime.tryParse(item['created_at'].toString()) ?? DateTime.now()
                    : DateTime.now(),
              );
              await DatabaseHelper.instance.createUser(newUser);
            }
          }
        }
      } catch (e) {
        debugPrint('Online client sync bypassed (using offline store): $e');
      }

      // 2. Fetch all local users & compute local stats
      final allUsers = await DatabaseHelper.instance.getAllUsers();
      final Map<int, Map<String, dynamic>> statsMap = {};
      double totalSales = 0.0;
      int activeCount = 0;
      int inactiveCount = 0;

      for (var u in allUsers) {
        if (u.id != null) {
          final stats = await DatabaseHelper.instance.getUserStats(u.id!);
          statsMap[u.id!] = stats;
          totalSales += (stats['total_sales'] as num?)?.toDouble() ?? 0.0;
        }

        if (u.role != 'admin') {
          if (u.isActive) {
            activeCount++;
          } else {
            inactiveCount++;
          }
        }
      }

      if (mounted) {
        setState(() {
          _users = allUsers;
          _userStats = statsMap;
          _totalUsers = allUsers.length;
          _activeClients = activeCount;
          _inactiveClients = inactiveCount;
          _totalNetworkSales = totalSales;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading clients: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<User> get _filteredUsers {
    return _users.where((user) {
      // Role & status filter
      if (_filter == 'active' && (!user.isActive || user.isAdmin)) return false;
      if (_filter == 'inactive' && (user.isActive || user.isAdmin)) return false;
      if (_filter == 'admins' && !user.isAdmin) return false;

      // Search query
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchUsername = user.username.toLowerCase().contains(q);
        final matchName = user.fullName.toLowerCase().contains(q);
        final matchEmail = user.email?.toLowerCase().contains(q) ?? false;
        return matchUsername || matchName || matchEmail;
      }

      return true;
    }).toList();
  }

  Future<void> _toggleUserStatus(User user) async {
    final currentUserId = context.read<AuthProvider>().currentUser?.id;
    if (user.id == currentUserId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You cannot deactivate your own administrator account.'),
          backgroundColor: AppTheme.accentAmber,
        ),
      );
      return;
    }

    final newStatus = !user.isActive;
    final actionName = newStatus ? 'activate' : 'deactivate';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${newStatus ? 'Activate' : 'Deactivate'} Account?'),
        content: Text(
          'Are you sure you want to $actionName @${user.username} (${user.fullName})?'
          '${!newStatus ? ' They will be blocked from logging into the POS until reactivated.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: newStatus ? AppTheme.accentTeal : AppTheme.accentRose,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(newStatus ? 'Activate' : 'Deactivate'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // Try online
      if (user.id != null) {
        try {
          await ApiService.instance.toggleClientStatus(user.id!);
        } catch (_) {}
        await DatabaseHelper.instance.updateUserStatus(user.id!, newStatus);
      }

      HapticFeedback.mediumImpact();
      await _loadClients();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('@${user.username} is now ${newStatus ? 'Active' : 'Deactivated'}.'),
            backgroundColor: newStatus ? AppTheme.accentTeal : AppTheme.accentRose,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update status: $e'),
            backgroundColor: AppTheme.accentRose,
          ),
        );
      }
    }
  }

  Future<void> _deleteUser(User user) async {
    final currentUserId = context.read<AuthProvider>().currentUser?.id;
    if (user.id == currentUserId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You cannot delete your own administrator account.'),
          backgroundColor: AppTheme.accentRose,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Client Account?'),
        content: Text(
          'Warning: This action will permanently remove @${user.username} (${user.fullName}), '
          'including their store products, sales history, and debt records. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.accentRose),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      if (user.id != null) {
        try {
          await ApiService.instance.deleteAdminClient(user.id!);
        } catch (_) {}
        await DatabaseHelper.instance.deleteUser(user.id!);
      }

      HapticFeedback.heavyImpact();
      await _loadClients();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Client @${user.username} deleted.'),
            backgroundColor: AppTheme.accentRose,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete client: $e'),
            backgroundColor: AppTheme.accentRose,
          ),
        );
      }
    }
  }

  void _showAddClientDialog() {
    final formKey = GlobalKey<FormState>();
    final usernameController = TextEditingController();
    final fullNameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final pinController = TextEditingController();
    String selectedRole = 'client';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (modalCtx, setModalState) {
          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 24,
              top: 24,
              left: 20,
              right: 20,
            ),
            decoration: BoxDecoration(
              color: Theme.of(modalCtx).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: AppTheme.borderColor(modalCtx)),
            ),
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.accentOrange.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.person_add_rounded, color: AppTheme.accentOrange, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Add New Account',
                                style: Theme.of(modalCtx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              Text(
                                'Create a store client or additional administrator',
                                style: TextStyle(color: AppTheme.mutedText(modalCtx), fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(modalCtx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Role Selection Segment
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppTheme.cardBackground(modalCtx),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.borderColor(modalCtx)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setModalState(() => selectedRole = 'client'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: selectedRole == 'client' ? AppTheme.accentOrange : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  'Store Client',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: selectedRole == 'client' ? Colors.white : AppTheme.mutedText(modalCtx),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setModalState(() => selectedRole = 'admin'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: selectedRole == 'admin' ? AppTheme.accentPurple : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  'Administrator',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: selectedRole == 'admin' ? Colors.white : AppTheme.mutedText(modalCtx),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username *',
                        prefixIcon: Icon(Icons.alternate_email_rounded, size: 20),
                        hintText: 'e.g. johndoe',
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Username is required';
                        if (v.trim().length < 3) return 'Must be at least 3 characters';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: fullNameController,
                      decoration: const InputDecoration(
                        labelText: 'Full / Store Name *',
                        prefixIcon: Icon(Icons.storefront_rounded, size: 20),
                        hintText: 'e.g. John Sari-Sari Store',
                      ),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Full name is required' : null,
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email Address (Optional)',
                        prefixIcon: Icon(Icons.email_outlined, size: 20),
                        hintText: 'e.g. store@example.com',
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password *',
                        prefixIcon: Icon(Icons.lock_outline_rounded, size: 20),
                        hintText: 'Minimum 4 characters',
                      ),
                      validator: (v) => (v == null || v.length < 4) ? 'Password must be at least 4 characters' : null,
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: pinController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                      decoration: const InputDecoration(
                        labelText: 'Quick PIN (Optional, 4-6 digits)',
                        prefixIcon: Icon(Icons.pin_outlined, size: 20),
                        hintText: 'e.g. 1234',
                      ),
                    ),
                    const SizedBox(height: 24),

                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: selectedRole == 'admin' ? AppTheme.accentPurple : AppTheme.accentOrange,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () async {
                        if (!formKey.currentState!.validate()) return;
                        final username = usernameController.text.trim();
                        final fullName = fullNameController.text.trim();
                        final email = emailController.text.trim().isNotEmpty ? emailController.text.trim() : null;
                        final password = passwordController.text;
                        final pin = pinController.text.trim().isNotEmpty ? pinController.text.trim() : null;

                        Navigator.pop(ctx);
                        setState(() => _isLoading = true);

                        try {
                          int? newOnlineId;
                          try {
                            final res = await ApiService.instance.createAdminClient(
                              username: username,
                              fullName: fullName,
                              password: password,
                              email: email,
                              pin: pin,
                              role: selectedRole,
                              isActive: true,
                            );
                            if (res['user'] != null) {
                              newOnlineId = res['user']['id'];
                            }
                          } catch (_) {}

                          final newUser = User(
                            id: newOnlineId,
                            username: username,
                            password: password,
                            fullName: fullName,
                            email: email,
                            pin: pin,
                            role: selectedRole,
                            isActive: true,
                            createdAt: DateTime.now(),
                          );
                          await DatabaseHelper.instance.createUser(newUser);

                          HapticFeedback.mediumImpact();
                          await _loadClients();

                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Account @$username created successfully.'),
                                backgroundColor: AppTheme.accentTeal,
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error creating account: $e'),
                                backgroundColor: AppTheme.accentRose,
                              ),
                            );
                            setState(() => _isLoading = false);
                          }
                        }
                      },
                      child: const Text('Create Account', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showEditClientDialog(User user) {
    final formKey = GlobalKey<FormState>();
    final fullNameController = TextEditingController(text: user.fullName);
    final emailController = TextEditingController(text: user.email ?? '');
    String selectedRole = user.role;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (modalCtx, setModalState) {
          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 24,
              top: 24,
              left: 20,
              right: 20,
            ),
            decoration: BoxDecoration(
              color: Theme.of(modalCtx).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: AppTheme.borderColor(modalCtx)),
            ),
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.accentTeal.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.edit_note_rounded, color: AppTheme.accentTeal, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Edit Account',
                                style: Theme.of(modalCtx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              Text(
                                '@${user.username}',
                                style: TextStyle(color: AppTheme.mutedText(modalCtx), fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(modalCtx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Role switch
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppTheme.cardBackground(modalCtx),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.borderColor(modalCtx)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setModalState(() => selectedRole = 'client'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: selectedRole == 'client' ? AppTheme.accentOrange : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  'Store Client',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: selectedRole == 'client' ? Colors.white : AppTheme.mutedText(modalCtx),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setModalState(() => selectedRole = 'admin'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: selectedRole == 'admin' ? AppTheme.accentPurple : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  'Administrator',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: selectedRole == 'admin' ? Colors.white : AppTheme.mutedText(modalCtx),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: fullNameController,
                      decoration: const InputDecoration(
                        labelText: 'Full / Store Name *',
                        prefixIcon: Icon(Icons.storefront_rounded, size: 20),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Full name is required' : null,
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email Address',
                        prefixIcon: Icon(Icons.email_outlined, size: 20),
                      ),
                    ),
                    const SizedBox(height: 24),

                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.accentTeal,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () async {
                        if (!formKey.currentState!.validate()) return;
                        final newFullName = fullNameController.text.trim();
                        final newEmail = emailController.text.trim().isNotEmpty ? emailController.text.trim() : null;

                        Navigator.pop(ctx);
                        setState(() => _isLoading = true);

                        try {
                          if (user.id != null) {
                            try {
                              await ApiService.instance.updateAdminClient(
                                user.id!,
                                fullName: newFullName,
                                email: newEmail,
                                role: selectedRole,
                              );
                            } catch (_) {}

                            final updated = user.copyWith(
                              fullName: newFullName,
                              email: newEmail,
                              role: selectedRole,
                            );
                            await DatabaseHelper.instance.updateUser(updated);
                          }

                          HapticFeedback.mediumImpact();
                          await _loadClients();

                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Account details updated.'),
                                backgroundColor: AppTheme.accentTeal,
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to update account: $e'),
                                backgroundColor: AppTheme.accentRose,
                              ),
                            );
                            setState(() => _isLoading = false);
                          }
                        }
                      },
                      child: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showResetCredentialsDialog(User user) {
    final formKey = GlobalKey<FormState>();
    final passwordController = TextEditingController();
    final pinController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          top: 24,
          left: 20,
          right: 20,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: AppTheme.borderColor(context)),
        ),
        child: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.accentAmber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.password_rounded, color: AppTheme.accentAmber, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Reset Credentials',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            'Reset password or quick PIN for @${user.username}',
                            style: TextStyle(color: AppTheme.mutedText(context), fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                TextFormField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'New Password (Optional)',
                    prefixIcon: Icon(Icons.lock_reset_rounded, size: 20),
                    hintText: 'Leave empty to keep unchanged',
                  ),
                  validator: (v) {
                    if (v != null && v.isNotEmpty && v.length < 4) {
                      return 'Password must be at least 4 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: pinController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                  decoration: const InputDecoration(
                    labelText: 'New PIN (Optional, 4-6 digits)',
                    prefixIcon: Icon(Icons.pin_outlined, size: 20),
                    hintText: 'Leave empty to keep unchanged',
                  ),
                ),
                const SizedBox(height: 24),

                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.accentAmber,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    final newPassword = passwordController.text;
                    final newPin = pinController.text.trim();

                    if (newPassword.isEmpty && newPin.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter a new password or PIN.')),
                      );
                      return;
                    }

                    Navigator.pop(ctx);
                    setState(() => _isLoading = true);

                    try {
                      if (user.id != null) {
                        try {
                          await ApiService.instance.resetClientCredentials(
                            user.id!,
                            password: newPassword.isNotEmpty ? newPassword : null,
                            pin: newPin.isNotEmpty ? newPin : null,
                          );
                        } catch (_) {}

                        await DatabaseHelper.instance.updateUserCredentials(
                          user.id!,
                          password: newPassword.isNotEmpty ? newPassword : null,
                          pin: newPin.isNotEmpty ? newPin : null,
                        );
                      }

                      HapticFeedback.mediumImpact();
                      await _loadClients();

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Credentials updated for @${user.username}.'),
                            backgroundColor: AppTheme.accentTeal,
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Failed to update credentials: $e'),
                            backgroundColor: AppTheme.accentRose,
                          ),
                        );
                        setState(() => _isLoading = false);
                      }
                    }
                  },
                  child: const Text('Update Credentials', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showClientDetails(User user) {
    final stats = _userStats[user.id] ?? {};
    final productsCount = stats['products_count'] ?? 0;
    final txCount = stats['transactions_count'] ?? 0;
    final totalSales = (stats['total_sales'] as num?)?.toDouble() ?? 0.0;
    final debtsCount = stats['debts_count'] ?? 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: AppTheme.borderColor(context)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: user.isAdmin ? AppTheme.accentPurple : AppTheme.accentOrange,
                  child: Text(
                    user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              user.fullName,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildRoleChip(user.role),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '@${user.username} ${user.email != null ? '• ${user.email}' : ''}',
                        style: TextStyle(color: AppTheme.mutedText(context), fontSize: 13),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Metrics Grid
            Text(
              'STORE PERFORMANCE & ACTIVITY',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: AppTheme.mutedText(context),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildMetricTile(
                    title: 'Total Sales',
                    value: _currencyFormat.format(totalSales),
                    icon: Icons.payments_rounded,
                    color: AppTheme.accentTeal,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricTile(
                    title: 'Transactions',
                    value: txCount.toString(),
                    icon: Icons.receipt_long_rounded,
                    color: AppTheme.accentOrange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildMetricTile(
                    title: 'Products in Catalog',
                    value: productsCount.toString(),
                    icon: Icons.inventory_2_rounded,
                    color: AppTheme.accentIndigo,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricTile(
                    title: 'Unpaid Debts',
                    value: debtsCount.toString(),
                    icon: Icons.assignment_late_rounded,
                    color: debtsCount > 0 ? AppTheme.accentRose : AppTheme.mutedText(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Account status info
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.cardBackground(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.borderColor(context)),
              ),
              child: Row(
                children: [
                  Icon(
                    user.isActive ? Icons.check_circle_rounded : Icons.block_rounded,
                    color: user.isActive ? AppTheme.accentTeal : AppTheme.accentRose,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      user.isActive
                          ? 'Account active and allowed to process sales.'
                          : 'Account deactivated. Login access is currently restricted.',
                      style: TextStyle(
                        fontSize: 13,
                        color: user.isActive ? AppTheme.accentTeal : AppTheme.accentRose,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleChip(String role) {
    final isAdmin = role.toLowerCase() == 'admin';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (isAdmin ? AppTheme.accentPurple : AppTheme.accentOrange).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isAdmin ? 'ADMIN' : 'CLIENT',
        style: TextStyle(
          color: isAdmin ? AppTheme.accentPurple : AppTheme.accentOrange,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildMetricTile({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 12, color: AppTheme.mutedText(context), fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required Gradient gradient,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.white, size: 18),
              ),
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredUsers;
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Client Management'),
        actions: [
          IconButton(
            tooltip: 'Sync & Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadClients,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.accentOrange,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Add Account', style: TextStyle(fontWeight: FontWeight.w700)),
        onPressed: _showAddClientDialog,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: RefreshIndicator(
            onRefresh: _loadClients,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                // Top Overview Metrics Grid
                if (isDesktop)
                  Row(
                    children: [
                      Expanded(
                        child: _buildOverviewCard(
                          label: 'Total Users',
                          value: _totalUsers.toString(),
                          icon: Icons.people_alt_rounded,
                          color: AppTheme.accentIndigo,
                          gradient: AppTheme.indigoGradient,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildOverviewCard(
                          label: 'Active Clients',
                          value: _activeClients.toString(),
                          icon: Icons.verified_user_rounded,
                          color: AppTheme.accentTeal,
                          gradient: AppTheme.tealGradient,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildOverviewCard(
                          label: 'Deactivated',
                          value: _inactiveClients.toString(),
                          icon: Icons.block_rounded,
                          color: AppTheme.accentRose,
                          gradient: AppTheme.roseGradient,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildOverviewCard(
                          label: 'Total Sales',
                          value: _currencyFormat.format(_totalNetworkSales),
                          icon: Icons.account_balance_wallet_rounded,
                          color: AppTheme.accentOrange,
                          gradient: AppTheme.orangeGradient,
                        ),
                      ),
                    ],
                  )
                else
                  Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildOverviewCard(
                              label: 'Total Users',
                              value: _totalUsers.toString(),
                              icon: Icons.people_alt_rounded,
                              color: AppTheme.accentIndigo,
                              gradient: AppTheme.indigoGradient,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildOverviewCard(
                              label: 'Active Clients',
                              value: _activeClients.toString(),
                              icon: Icons.verified_user_rounded,
                              color: AppTheme.accentTeal,
                              gradient: AppTheme.tealGradient,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildOverviewCard(
                              label: 'Deactivated',
                              value: _inactiveClients.toString(),
                              icon: Icons.block_rounded,
                              color: AppTheme.accentRose,
                              gradient: AppTheme.roseGradient,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildOverviewCard(
                              label: 'Total Sales',
                              value: _currencyFormat.format(_totalNetworkSales),
                              icon: Icons.account_balance_wallet_rounded,
                              color: AppTheme.accentOrange,
                              gradient: AppTheme.orangeGradient,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                const SizedBox(height: 24),

                // Search & Filter controls
                TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  decoration: InputDecoration(
                    hintText: 'Search by username, full name, or email...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 22),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 20),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 12),

                // Filter chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('all', 'All Accounts (${_users.length})'),
                      const SizedBox(width: 8),
                      _buildFilterChip('active', 'Active ($_activeClients)'),
                      const SizedBox(width: 8),
                      _buildFilterChip('inactive', 'Deactivated ($_inactiveClients)'),
                      const SizedBox(width: 8),
                      _buildFilterChip('admins', 'Admins (${_users.where((u) => u.isAdmin).length})'),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Client List
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (filtered.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
                    alignment: Alignment.center,
                    child: Column(
                      children: [
                        Icon(Icons.person_search_rounded, size: 54, color: AppTheme.mutedText(context)),
                        const SizedBox(height: 12),
                        Text(
                          'No accounts found',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.mutedText(context)),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _searchQuery.isNotEmpty ? 'Try adjusting your search criteria.' : 'Create an account to get started.',
                          style: TextStyle(fontSize: 13, color: AppTheme.mutedText(context)),
                        ),
                      ],
                    ),
                  )
                else
                  ...filtered.map((user) => _buildClientCard(user)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String filterKey, String label) {
    final isSelected = _filter == filterKey;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _filter = filterKey),
      selectedColor: AppTheme.accentOrange,
      labelStyle: TextStyle(
        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
        fontSize: 12,
        color: isSelected ? Colors.white : AppTheme.mutedText(context),
      ),
    );
  }

  Widget _buildClientCard(User user) {
    final stats = _userStats[user.id] ?? {};
    final productsCount = stats['products_count'] ?? 0;
    final txCount = stats['transactions_count'] ?? 0;
    final totalSales = (stats['total_sales'] as num?)?.toDouble() ?? 0.0;
    final currentUserId = context.read<AuthProvider>().currentUser?.id;
    final isSelf = user.id == currentUserId;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: user.isActive ? AppTheme.borderColor(context) : AppTheme.accentRose.withValues(alpha: 0.3),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _showClientDetails(user),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: user.isAdmin
                          ? AppTheme.accentPurple
                          : (user.isActive ? AppTheme.accentOrange : AppTheme.mutedText(context)),
                      child: Text(
                        user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : '?',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  user.fullName,
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              _buildRoleChip(user.role),
                              if (isSelf) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.accentTeal.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'YOU',
                                    style: TextStyle(color: AppTheme.accentTeal, fontSize: 9, fontWeight: FontWeight.w800),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '@${user.username} ${user.email != null ? '• ${user.email}' : ''}',
                            style: TextStyle(color: AppTheme.mutedText(context), fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    // Quick Action Menu
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert_rounded),
                      onSelected: (val) {
                        switch (val) {
                          case 'details':
                            _showClientDetails(user);
                            break;
                          case 'edit':
                            _showEditClientDialog(user);
                            break;
                          case 'credentials':
                            _showResetCredentialsDialog(user);
                            break;
                          case 'toggle_status':
                            _toggleUserStatus(user);
                            break;
                          case 'delete':
                            _deleteUser(user);
                            break;
                        }
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(
                          value: 'details',
                          child: Row(
                            children: [
                              Icon(Icons.bar_chart_rounded, size: 18),
                              SizedBox(width: 10),
                              Text('View Store Overview'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit_rounded, size: 18),
                              SizedBox(width: 10),
                              Text('Edit Information'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'credentials',
                          child: Row(
                            children: [
                              Icon(Icons.lock_reset_rounded, size: 18),
                              SizedBox(width: 10),
                              Text('Reset Password / PIN'),
                            ],
                          ),
                        ),
                        if (!isSelf)
                          PopupMenuItem(
                            value: 'toggle_status',
                            child: Row(
                              children: [
                                Icon(
                                  user.isActive ? Icons.block_rounded : Icons.check_circle_rounded,
                                  color: user.isActive ? AppTheme.accentRose : AppTheme.accentTeal,
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                                Text(user.isActive ? 'Deactivate Account' : 'Activate Account'),
                              ],
                            ),
                          ),
                        if (!isSelf)
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_forever_rounded, color: AppTheme.accentRose, size: 18),
                                SizedBox(width: 10),
                                Text('Delete Client', style: TextStyle(color: AppTheme.accentRose)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Metrics Strip
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      _buildMiniStat(Icons.inventory_2_outlined, '$productsCount items'),
                      const SizedBox(width: 16),
                      _buildMiniStat(Icons.receipt_outlined, '$txCount sales'),
                      const Spacer(),
                      Text(
                        _currencyFormat.format(totalSales),
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppTheme.accentTeal),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Status Bar + Quick Toggle
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: user.isActive ? AppTheme.accentTeal : AppTheme.accentRose,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      user.isActive ? 'Active' : 'Deactivated',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: user.isActive ? AppTheme.accentTeal : AppTheme.accentRose,
                      ),
                    ),
                    const Spacer(),
                    if (!isSelf)
                      Row(
                        children: [
                          Text(
                            user.isActive ? 'Enabled' : 'Disabled',
                            style: TextStyle(fontSize: 11, color: AppTheme.mutedText(context), fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 6),
                          Transform.scale(
                            scale: 0.75,
                            child: Switch(
                              value: user.isActive,
                              activeThumbColor: AppTheme.accentTeal,
                              onChanged: (_) => _toggleUserStatus(user),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniStat(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppTheme.mutedText(context)),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(fontSize: 12, color: AppTheme.mutedText(context), fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
