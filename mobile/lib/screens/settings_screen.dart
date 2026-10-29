import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/app_theme.dart';
import '../data/database_helper.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late final TextEditingController _phoneController;
  late final TextEditingController _gcashNumberController;
  String? _gcashQrPath;
  String? _businessPhotoPath;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _nameController = TextEditingController(text: settings.storeName);
    _addressController = TextEditingController(text: settings.storeAddress);
    _phoneController = TextEditingController(text: settings.storePhone);
    _gcashNumberController = TextEditingController(text: settings.gcashNumber);
    _gcashQrPath = settings.gcashQrPath;
    _businessPhotoPath = settings.businessPhotoPath;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _gcashNumberController.dispose();
    super.dispose();
  }

  void _saveSettings() {
    if (_formKey.currentState!.validate()) {
      HapticFeedback.mediumImpact();
      final settings = context.read<SettingsProvider>();
      settings.updateStoreInfo(
        name: _nameController.text.trim(),
        address: _addressController.text.trim(),
        phone: _phoneController.text.trim(),
        gcashNumber: _gcashNumberController.text.trim(),
        gcashQrPath: _gcashQrPath ?? '',
        businessPhotoPath: _businessPhotoPath ?? settings.businessPhotoPath,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text('Store & payment settings saved'),
            ],
          ),
          backgroundColor: AppTheme.accentTeal,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<SettingsProvider>();
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    final currentBusinessPhoto =
        _businessPhotoPath ?? settings.businessPhotoPath;
    final hasValidBusinessPhoto = currentBusinessPhoto.isNotEmpty &&
        File(currentBusinessPhoto).existsSync();
    final hasValidQr = _gcashQrPath != null &&
        _gcashQrPath!.isNotEmpty &&
        File(_gcashQrPath!).existsSync();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: _saveSettings,
              child: const Text('Save'),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── 1. User Profile Banner ──
                if (user != null)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: AppTheme.heroDarkGradient,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: _showBusinessPhotoPickerSheet,
                          child: Tooltip(
                            message: 'Change Business Photo',
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  clipBehavior: Clip.antiAlias,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    gradient: hasValidBusinessPhoto
                                        ? null
                                        : AppTheme.orangeGradient,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color:
                                          Colors.white.withValues(alpha: 0.2),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: hasValidBusinessPhoto
                                      ? Image.file(
                                          File(currentBusinessPhoto),
                                          width: 56,
                                          height: 56,
                                          fit: BoxFit.cover,
                                        )
                                      : Text(
                                          user.fullName.isNotEmpty
                                              ? user.fullName[0].toUpperCase()
                                              : 'T',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 22,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                ),
                                Positioned(
                                  right: -2,
                                  bottom: -2,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: AppTheme.accentOrange,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: const Color(0xFF1E222D),
                                        width: 2,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.camera_alt_rounded,
                                      size: 11,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user.fullName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '@${user.username}',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.65),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: (user.pin != null
                                    ? AppTheme.accentTeal
                                    : AppTheme.accentAmber)
                                .withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                user.pin != null
                                    ? Icons.verified_user_rounded
                                    : Icons.pin_outlined,
                                size: 14,
                                color: user.pin != null
                                    ? AppTheme.accentTeal
                                    : AppTheme.accentAmber,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                user.pin != null ? 'PIN Active' : 'No PIN',
                                style: TextStyle(
                                  color: user.pin != null
                                      ? AppTheme.accentTeal
                                      : AppTheme.accentAmber,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 24),

                // ── 2. Unified Store & Payment Form ──
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _SettingsSectionLabel('STORE & RECEIPT DETAILS'),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: theme.cardTheme.color,
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusLg),
                          border: Border.all(
                            color: AppTheme.borderColor(context),
                          ),
                          boxShadow: AppTheme.cardShadow(context),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // ── Business Photo Picker ──
                            Row(
                              children: [
                                GestureDetector(
                                  onTap: _showBusinessPhotoPickerSheet,
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      Container(
                                        height: 88,
                                        width: 88,
                                        clipBehavior: Clip.antiAlias,
                                        decoration: BoxDecoration(
                                          color: AppTheme.subtleSurface(context),
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          border: Border.all(
                                            color:
                                                AppTheme.borderColor(context),
                                          ),
                                        ),
                                        child: hasValidBusinessPhoto
                                            ? Image.file(
                                                File(currentBusinessPhoto),
                                                fit: BoxFit.cover,
                                              )
                                            : Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    Icons.storefront_outlined,
                                                    size: 32,
                                                    color: AppTheme.mutedText(
                                                        context),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    'Add Photo',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: AppTheme.mutedText(
                                                          context),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                      ),
                                      Positioned(
                                        right: 4,
                                        bottom: 4,
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: AppTheme.accentOrange,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: theme.cardTheme.color ??
                                                  Colors.white,
                                              width: 1.5,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.camera_alt_rounded,
                                            size: 12,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Business Photo',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Logo or storefront image displayed on POS headers and receipts.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          height: 1.4,
                                          color: AppTheme.mutedText(context),
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          OutlinedButton.icon(
                                            onPressed:
                                                _showBusinessPhotoPickerSheet,
                                            style: OutlinedButton.styleFrom(
                                              minimumSize: const Size(0, 36),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 12,
                                              ),
                                            ),
                                            icon: const Icon(
                                              Icons.upload_outlined,
                                              size: 16,
                                            ),
                                            label: Text(
                                              hasValidBusinessPhoto
                                                  ? 'Replace'
                                                  : 'Upload',
                                              style: const TextStyle(
                                                  fontSize: 12),
                                            ),
                                          ),
                                          if (hasValidBusinessPhoto)
                                            TextButton(
                                              onPressed: _removeBusinessPhoto,
                                              style: TextButton.styleFrom(
                                                foregroundColor:
                                                    AppTheme.accentRose,
                                                minimumSize:
                                                    const Size(0, 36),
                                              ),
                                              child: const Text(
                                                'Remove',
                                                style: TextStyle(fontSize: 12),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Divider(
                              height: 1,
                              color: AppTheme.borderColor(context),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _nameController,
                              decoration: const InputDecoration(
                                labelText: 'Store Name',
                                prefixIcon: Icon(Icons.storefront_outlined),
                              ),
                              validator: (v) =>
                                  v == null || v.trim().isEmpty ? 'Required' : null,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _addressController,
                              decoration: const InputDecoration(
                                labelText: 'Business Address',
                                prefixIcon: Icon(Icons.location_on_outlined),
                              ),
                              validator: (v) =>
                                  v == null || v.trim().isEmpty ? 'Required' : null,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'Contact Number',
                                prefixIcon: Icon(Icons.phone_outlined),
                              ),
                              validator: (v) =>
                                  v == null || v.trim().isEmpty ? 'Required' : null,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      const _SettingsSectionLabel('GCASH PAYMENT SETUP'),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: theme.cardTheme.color,
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusLg),
                          border: Border.all(
                            color: AppTheme.borderColor(context),
                          ),
                          boxShadow: AppTheme.cardShadow(context),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _gcashNumberController,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'GCash Account Number (Optional)',
                                hintText: '09XX XXX XXXX',
                                prefixIcon: Icon(
                                  Icons.account_balance_wallet_outlined,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                GestureDetector(
                                  onTap: _pickGcashQr,
                                  child: Container(
                                    height: 100,
                                    width: 100,
                                    clipBehavior: Clip.antiAlias,
                                    decoration: BoxDecoration(
                                      color: AppTheme.subtleSurface(context),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: AppTheme.borderColor(context),
                                      ),
                                    ),
                                    child: hasValidQr
                                        ? Image.file(
                                            File(_gcashQrPath!),
                                            fit: BoxFit.cover,
                                          )
                                        : Icon(
                                            Icons.qr_code_2_rounded,
                                            size: 40,
                                            color: AppTheme.mutedText(context),
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'GCash QR Code',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Displayed automatically at checkout when customers pay via GCash.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          height: 1.4,
                                          color: AppTheme.mutedText(context),
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 8,
                                        children: [
                                          OutlinedButton.icon(
                                            onPressed: _pickGcashQr,
                                            style: OutlinedButton.styleFrom(
                                              minimumSize: const Size(0, 36),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                  ),
                                            ),
                                            icon: const Icon(
                                              Icons.upload_outlined,
                                              size: 16,
                                            ),
                                            label: Text(
                                              hasValidQr ? 'Replace' : 'Upload',
                                              style:
                                                  const TextStyle(fontSize: 12),
                                            ),
                                          ),
                                          if (hasValidQr)
                                            TextButton(
                                              onPressed: () => setState(
                                                () => _gcashQrPath = '',
                                              ),
                                              style: TextButton.styleFrom(
                                                foregroundColor:
                                                    AppTheme.accentRose,
                                                minimumSize: const Size(0, 36),
                                              ),
                                              child: const Text(
                                                'Remove',
                                                style: TextStyle(fontSize: 12),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _saveSettings,
                        icon: const Icon(Icons.check_rounded, size: 20),
                        label: const Text('Save Store & Payment Info'),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // ── 3. Appearance & Preferences ──
                const _SettingsSectionLabel('APPEARANCE'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.cardTheme.color,
                    borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                    border: Border.all(color: AppTheme.borderColor(context)),
                    boxShadow: AppTheme.cardShadow(context),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.contrast_rounded,
                            size: 20,
                            color: AppTheme.accentOrange,
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Theme Mode',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppTheme.subtleSurface(context),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            _ThemeModeOption(
                              label: 'System',
                              icon: Icons.brightness_auto_rounded,
                              isSelected:
                                  settings.themeMode == ThemeMode.system,
                              onTap: () => settings.setThemeMode(
                                ThemeMode.system,
                              ),
                            ),
                            _ThemeModeOption(
                              label: 'Light',
                              icon: Icons.light_mode_rounded,
                              isSelected: settings.themeMode == ThemeMode.light,
                              onTap: () => settings.setThemeMode(
                                ThemeMode.light,
                              ),
                            ),
                            _ThemeModeOption(
                              label: 'Dark',
                              icon: Icons.dark_mode_rounded,
                              isSelected: settings.themeMode == ThemeMode.dark,
                              onTap: () => settings.setThemeMode(
                                ThemeMode.dark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // ── 4. Security ──
                const _SettingsSectionLabel('SECURITY & ACCESS'),
                const SizedBox(height: 8),
                _SettingsGroupCard(
                  children: [
                    _SettingsTile(
                      icon: Icons.dialpad_rounded,
                      iconColor: AppTheme.accentOrange,
                      title: 'Quick 4-Digit PIN',
                      subtitle: user?.pin == null
                          ? 'Set up fast PIN unlock & idle lock'
                          : 'Active • Locks after 2 min of inactivity',
                      onTap: () => _showSetupPinDialog(context),
                    ),
                    Divider(height: 1, color: AppTheme.borderColor(context)),
                    _SettingsTile(
                      icon: Icons.lock_outline_rounded,
                      iconColor: AppTheme.accentIndigo,
                      title: 'Change Password',
                      subtitle: 'Update your account login password',
                      onTap: () => _showChangePasswordDialog(context),
                    ),
                  ],
                ),

                const SizedBox(height: 28),

                // ── 4.5 Cloud Sync & Online API ──
                const _SettingsSectionLabel('CLOUD SYNC & ONLINE BACKEND'),
                const SizedBox(height: 8),
                _SettingsGroupCard(
                  children: [
                    ValueListenableBuilder<bool>(
                      valueListenable: SyncService.instance.isOnline,
                      builder: (context, online, _) {
                        return _SettingsTile(
                          icon: online ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                          iconColor: online ? AppTheme.accentTeal : Colors.grey,
                          title: online ? 'Cloud Server Connected' : 'Working Offline (SQLite)',
                          subtitle: ApiService.instance.baseUrl,
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: (online ? AppTheme.accentTeal : Colors.grey).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              online ? 'ONLINE' : 'OFFLINE',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: online ? AppTheme.accentTeal : Colors.grey,
                              ),
                            ),
                          ),
                          onTap: () => _showChangeServerUrlDialog(context),
                        );
                      },
                    ),
                    Divider(height: 1, color: AppTheme.borderColor(context)),
                    ValueListenableBuilder<bool>(
                      valueListenable: SyncService.instance.isSyncing,
                      builder: (context, isSyncing, _) {
                        return _SettingsTile(
                          icon: Icons.sync_rounded,
                          iconColor: AppTheme.accentOrange,
                          title: isSyncing ? 'Syncing...' : 'Sync Store with Cloud Now',
                          subtitle: 'Uploads offline sales & downloads latest cloud catalog',
                          trailing: isSyncing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                          onTap: (isSyncing || user == null) ? null : () => _handleManualSync(user.id!),
                        );
                      },
                    ),
                    Divider(height: 1, color: AppTheme.borderColor(context)),
                    _SettingsTile(
                      icon: Icons.network_check_rounded,
                      iconColor: AppTheme.accentIndigo,
                      title: 'Test Server Connection',
                      subtitle: 'Pings the configured Laravel / Render endpoint',
                      onTap: _handleTestConnection,
                    ),
                  ],
                ),

                const SizedBox(height: 28),

                // ── 5. Data Management ──
                const _SettingsSectionLabel('DATABASE BACKUP'),
                const SizedBox(height: 8),
                _SettingsGroupCard(
                  children: [
                    _SettingsTile(
                      icon: Icons.cloud_upload_outlined,
                      iconColor: AppTheme.accentTeal,
                      title: 'Backup Store Data',
                      subtitle: 'Export SQLite database file to share or save',
                      onTap: _handleBackup,
                    ),
                    Divider(height: 1, color: AppTheme.borderColor(context)),
                    _SettingsTile(
                      icon: Icons.settings_backup_restore_rounded,
                      iconColor: AppTheme.accentAmber,
                      title: 'Restore from Backup',
                      subtitle: 'Import a previously exported database file',
                      onTap: _handleRestore,
                    ),
                  ],
                ),

                const SizedBox(height: 28),

                // ── 6. Account & App Info ──
                const _SettingsSectionLabel('ACCOUNT'),
                const SizedBox(height: 8),
                _SettingsGroupCard(
                  children: [
                    _SettingsTile(
                      icon: Icons.info_outline_rounded,
                      iconColor: AppTheme.mutedText(context),
                      title: 'TindaKo POS Version',
                      subtitle: 'Offline-first Retail POS',
                      trailing: Text(
                        'v1.0.0',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: AppTheme.mutedText(context),
                        ),
                      ),
                    ),
                    Divider(height: 1, color: AppTheme.borderColor(context)),
                    _SettingsTile(
                      icon: Icons.logout_rounded,
                      iconColor: AppTheme.accentRose,
                      title: 'Sign Out',
                      titleColor: AppTheme.accentRose,
                      subtitle: 'Switch account or lock session',
                      onTap: () => _showLogoutDialog(context),
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

  Future<void> _pickGcashQr() async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null && mounted) {
      setState(() {
        _gcashQrPath = result.files.single.path;
      });
    }
  }

  Future<void> _pickBusinessPhoto(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 1000,
        maxHeight: 1000,
        imageQuality: 85,
      );

      if (pickedFile != null && mounted) {
        String finalPath = pickedFile.path;
        try {
          final dir = await getApplicationDocumentsDirectory();
          final ext = pickedFile.path.contains('.')
              ? pickedFile.path.split('.').last
              : 'jpg';
          final savedPath =
              '${dir.path}/business_photo_${DateTime.now().millisecondsSinceEpoch}.$ext';
          final savedFile = await File(pickedFile.path).copy(savedPath);
          finalPath = savedFile.path;
        } catch (_) {}

        setState(() {
          _businessPhotoPath = finalPath;
        });

        if (mounted) {
          context.read<SettingsProvider>().updateBusinessPhoto(finalPath);
        }
      }
    } catch (_) {
      final result = await FilePicker.pickFiles(type: FileType.image);
      if (result != null && result.files.single.path != null && mounted) {
        final path = result.files.single.path!;
        setState(() {
          _businessPhotoPath = path;
        });
        if (mounted) {
          context.read<SettingsProvider>().updateBusinessPhoto(path);
        }
      }
    }
  }

  void _removeBusinessPhoto() {
    setState(() {
      _businessPhotoPath = '';
    });
    context.read<SettingsProvider>().updateBusinessPhoto('');
  }

  void _showBusinessPhotoPickerSheet() {
    final currentPhoto = _businessPhotoPath ??
        context.read<SettingsProvider>().businessPhotoPath;
    final hasValidBusinessPhoto = currentPhoto.isNotEmpty &&
        File(currentPhoto).existsSync();

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardTheme.color,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppTheme.borderColor(ctx),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              Text(
                'Business Photo',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'Choose a store logo or business photo to display on the POS dashboard, receipts, and navigation.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.mutedText(ctx),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _SettingsImageSourceOption(
                    icon: Icons.camera_alt_rounded,
                    label: 'Camera',
                    onTap: () {
                      Navigator.pop(ctx);
                      _pickBusinessPhoto(ImageSource.camera);
                    },
                  ),
                  _SettingsImageSourceOption(
                    icon: Icons.photo_library_rounded,
                    label: 'Gallery',
                    onTap: () {
                      Navigator.pop(ctx);
                      _pickBusinessPhoto(ImageSource.gallery);
                    },
                  ),
                  if (hasValidBusinessPhoto)
                    _SettingsImageSourceOption(
                      icon: Icons.delete_outline_rounded,
                      label: 'Remove',
                      color: AppTheme.accentRose,
                      onTap: () {
                        Navigator.pop(ctx);
                        _removeBusinessPhoto();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Change Password',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: currentPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Current Password',
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: newPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'New Password',
                    ),
                    validator: (v) =>
                        (v?.length ?? 0) < 6 ? 'Minimum 6 characters' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: confirmPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirm New Password',
                    ),
                    validator: (v) => v != newPasswordController.text
                        ? 'Passwords do not match'
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                final messenger = ScaffoldMessenger.of(context);
                final auth = context.read<AuthProvider>();
                final navigator = Navigator.of(ctx);

                final success = await auth.changePassword(
                  currentPasswordController.text,
                  newPasswordController.text,
                );

                if (success && mounted) {
                  navigator.pop();
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Password updated successfully'),
                      backgroundColor: AppTheme.accentTeal,
                    ),
                  );
                } else if (!success && mounted) {
                  HapticFeedback.vibrate();
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Incorrect current password'),
                      backgroundColor: AppTheme.accentRose,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(minimumSize: const Size(100, 44)),
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _showSetupPinDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _SetupPinDialog(auth: context.read<AuthProvider>()),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Sign Out?',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text('Are you sure you want to sign out of TindaKo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              context.read<AuthProvider>().logout();
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentRose,
              minimumSize: const Size(100, 44),
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleTestConnection() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Text('Pinging server...'),
          ],
        ),
        duration: Duration(seconds: 1),
      ),
    );

    final ok = await ApiService.instance.checkConnection();
    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Text(ok ? 'Server reached successfully!' : 'Cannot reach server. Check URL / internet.'),
          ],
        ),
        backgroundColor: ok ? AppTheme.accentTeal : AppTheme.accentRose,
      ),
    );
  }

  Future<void> _handleManualSync(int userId) async {
    final messenger = ScaffoldMessenger.of(context);
    final success = await SyncService.instance.syncNow(userId);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              success ? Icons.check_circle_rounded : Icons.info_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Text(success ? 'Sync completed successfully!' : 'Sync failed or no internet.'),
          ],
        ),
        backgroundColor: success ? AppTheme.accentTeal : AppTheme.accentAmber,
      ),
    );
  }

  void _showChangeServerUrlDialog(BuildContext context) {
    final urlController = TextEditingController(text: ApiService.instance.baseUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Configure Cloud API URL'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the URL of your Laravel REST API (Local or Render live URL):',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(
                labelText: 'API Base URL',
                hintText: 'https://your-api.onrender.com/api',
                prefixIcon: Icon(Icons.link_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final newUrl = urlController.text.trim();
              if (newUrl.isNotEmpty) {
                await ApiService.instance.setBaseUrl(newUrl);
                setState(() {});
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleBackup() async {
    try {
      final path = await DatabaseHelper.instance.backupDatabase();
      final file = XFile(path);

      await SharePlus.instance.share(
        ShareParams(
          files: [file],
          text: 'TindaKo Database Backup',
          subject: 'TindaKo Backup ${DateTime.now().toString().split('.')[0]}',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup failed: $e'),
            backgroundColor: AppTheme.accentRose,
          ),
        );
      }
    }
  }

  Future<void> _handleRestore() async {
    try {
      final result = await FilePicker.pickFiles(type: FileType.any);

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);

        if (mounted) {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text(
                'Confirm Restore',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              content: const Text(
                'Restoring will replace all current products and transactions. Continue?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentRose,
                    minimumSize: const Size(120, 44),
                  ),
                  child: const Text('Restore Now'),
                ),
              ],
            ),
          );

          if (confirm == true) {
            await DatabaseHelper.instance.restoreDatabase(file);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Database restored! Please sign in again.'),
                  backgroundColor: AppTheme.accentTeal,
                ),
              );
              context.read<AuthProvider>().logout();
              Navigator.pop(context);
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Restore failed: $e'),
            backgroundColor: AppTheme.accentRose,
          ),
        );
      }
    }
  }
}

class _SettingsImageSourceOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _SettingsImageSourceOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final themeColor = color ?? AppTheme.accentOrange;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: themeColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: themeColor, size: 26),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: color ?? Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsSectionLabel extends StatelessWidget {
  final String text;
  const _SettingsSectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.0,
          color: AppTheme.mutedText(context),
        ),
      ),
    );
  }
}

class _SettingsGroupCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsGroupCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: AppTheme.borderColor(context)),
        boxShadow: AppTheme.cardShadow(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Color? titleColor;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.titleColor,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.mutedText(context),
                    ),
                  ),
                ],
              ),
            ),
            trailing ??
                (onTap != null
                    ? Icon(
                        Icons.chevron_right_rounded,
                        color: AppTheme.mutedText(context),
                      )
                    : const SizedBox.shrink()),
          ],
        ),
      ),
    );
  }
}

class _ThemeModeOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeModeOption({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? theme.cardTheme.color : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: isSelected ? AppTheme.cardShadow(context) : const [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected
                    ? AppTheme.accentOrange
                    : AppTheme.mutedText(context),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected
                        ? AppTheme.accentOrange
                        : AppTheme.mutedText(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SetupPinDialog extends StatefulWidget {
  final AuthProvider auth;
  const _SetupPinDialog({required this.auth});

  @override
  State<_SetupPinDialog> createState() => _SetupPinDialogState();
}

class _SetupPinDialogState extends State<_SetupPinDialog> {
  late final TextEditingController _pinController;
  late final FocusNode _pinFocusNode;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _pinController = TextEditingController();
    _pinFocusNode = FocusNode()..addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _pinFocusNode.removeListener(_onFocusChange);
    _pinFocusNode.dispose();
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pinText = _pinController.text;

    return AlertDialog(
      title: const Text(
        'Setup Quick PIN',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      content: Stack(
        children: [
          Opacity(
            opacity: 0.0,
            child: SizedBox(
              width: 1,
              height: 1,
              child: TextField(
                controller: _pinController,
                focusNode: _pinFocusNode,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 4,
                autofocus: true,
                onChanged: (_) {
                  setState(() => _errorMessage = null);
                },
                decoration: const InputDecoration(counterText: ''),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Enter a 4-digit PIN for quick terminal sign-in and idle lock.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.mutedText(context),
                ),
              ),
              const SizedBox(height: 22),
              GestureDetector(
                onTap: () => _pinFocusNode.requestFocus(),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(4, (index) {
                    final hasDigit = pinText.length > index;
                    final digit = hasDigit ? pinText[index] : '';
                    final isFocused =
                        _pinFocusNode.hasFocus && pinText.length == index;

                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 52,
                      height: 60,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppTheme.subtleSurface(context),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isFocused
                              ? AppTheme.accentOrange
                              : AppTheme.borderColor(context),
                          width: isFocused ? 2 : 1,
                        ),
                      ),
                      child: Text(
                        digit,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.accentOrange,
                          fontFeatures: AppTheme.tabularFigures,
                        ),
                      ),
                    );
                  }),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: const TextStyle(
                    color: AppTheme.accentRose,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            final pin = _pinController.text;
            if (pin.length != 4 || int.tryParse(pin) == null) {
              setState(() => _errorMessage = 'Enter all 4 digits');
              return;
            }

            final messenger = ScaffoldMessenger.of(context);
            final navigator = Navigator.of(context);

            final success = await widget.auth.updatePin(pin);
            if (success && mounted) {
              navigator.pop();
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('Quick PIN updated successfully'),
                  backgroundColor: AppTheme.accentTeal,
                ),
              );
            }
          },
          style: ElevatedButton.styleFrom(minimumSize: const Size(100, 44)),
          child: const Text('Save PIN'),
        ),
      ],
    );
  }
}
