import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YouTube Music Downloader',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      home: const HomeTabs(),
    );
  }
}

// ---------------- ANA SEKMELER ----------------
class HomeTabs extends StatefulWidget {
  const HomeTabs({super.key});

  @override
  State<HomeTabs> createState() => _HomeTabsState();
}

class _HomeTabsState extends State<HomeTabs> with TickerProviderStateMixin {
  int _currentIndex = 0;
  final AudioPlayer _audioPlayer = AudioPlayer();
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      PlaylistDownloader(audioPlayer: _audioPlayer),
      DownloadedFiles(audioPlayer: _audioPlayer),
      AudioPlayerPage(audioPlayer: _audioPlayer),
      SettingsPage(),
    ];

    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: tabs[_currentIndex],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
          _animationController.forward().then((_) {
            _animationController.reverse();
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.playlist_play_outlined),
            selectedIcon: Icon(Icons.playlist_play),
            label: "Playlist",
          ),
          NavigationDestination(
            icon: Icon(Icons.download_outlined),
            selectedIcon: Icon(Icons.download),
            label: "İndirilenler",
          ),
          NavigationDestination(
            icon: Icon(Icons.music_note_outlined),
            selectedIcon: Icon(Icons.music_note),
            label: "Oynatıcı",
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: "Ayarlar",
          ),
        ],
      ),
    );
  }
}

// ---------------- PLAYLIST TAB ----------------
class PlaylistDownloader extends StatefulWidget {
  final AudioPlayer audioPlayer;
  const PlaylistDownloader({super.key, required this.audioPlayer});

  @override
  State<PlaylistDownloader> createState() => _PlaylistDownloaderState();
}

class _PlaylistDownloaderState extends State<PlaylistDownloader>
    with TickerProviderStateMixin {
  final _yt = YoutubeExplode();
  final _controller = TextEditingController();
  List<Video> _videos = [];
  Set<Video> _selected = {};
  bool _isLoading = false;
  double _progress = 0.0;
  bool _isDownloading = false;
  String _currentDownload = '';
  late AnimationController _loadingController;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadingController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
    _loadRecentPlaylists();
  }

  @override
  void dispose() {
    _yt.close();
    _loadingController.dispose();
    super.dispose();
  }

  Future<void> _loadRecentPlaylists() async {
    await SharedPreferences.getInstance();
    // Bu listeyi UI'da gösterebiliriz
  }

  Future<void> _saveRecentPlaylist(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final recent = prefs.getStringList('recent_playlists') ?? [];
    recent.insert(0, url);
    if (recent.length > 5) recent.removeLast();
    await prefs.setStringList('recent_playlists', recent);
  }

  Future<void> _fetchPlaylist() async {
    if (_controller.text.trim().isEmpty) {
      _showSnackBar("Lütfen bir playlist linki girin!", isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
      _videos.clear();
      _selected.clear();
    });

    try {
      var playlist = await _yt.playlists.get(_controller.text);
      var videos = await _yt.playlists.getVideos(playlist.id).toList();

      await _saveRecentPlaylist(_controller.text);

      setState(() {
        _videos = videos;
        _selected.addAll(videos);
        _isLoading = false;
      });

      _showSnackBar("${videos.length} şarkı yüklendi!", isError: false);
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar(
        "Playlist yüklenirken hata: ${e.toString()}",
        isError: true,
      );
    }
  }

  Future<void> _downloadSelected() async {
    if (_selected.isEmpty) {
      _showSnackBar("Hiç şarkı seçmediniz!", isError: true);
      return;
    }

    var status = await Permission.storage.request();
    if (!status.isGranted) {
      _showSnackBar("Depolama izni gerekli!", isError: true);
      return;
    }

    setState(() {
      _isDownloading = true;
      _progress = 0.0;
    });

    var dir = await getApplicationDocumentsDirectory();
    var selectedList = _selected.toList();

    try {
      for (int i = 0; i < selectedList.length; i++) {
        var v = selectedList[i];
        setState(() {
          _currentDownload = v.title;
        });

        var manifest = await _yt.videos.streamsClient.getManifest(v.id);
        var audioStreamInfo = manifest.audioOnly.withHighestBitrate();
        var audioStream = _yt.videos.streamsClient.get(audioStreamInfo);

        var safeTitle = v.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        var filePath = '${dir.path}/$safeTitle.mp3';
        var file = File(filePath);

        if (await file.exists()) {
          setState(() {
            _progress = (i + 1) / selectedList.length;
          });
          continue; // Dosya zaten var, atla
        }

        var fileSink = file.openWrite();
        var downloaded = 0;
        var totalSize = audioStreamInfo.size.totalBytes;

        await for (final data in audioStream) {
          downloaded += data.length;
          fileSink.add(data);

          setState(() {
            _progress = (i + (downloaded / totalSize)) / selectedList.length;
          });
        }

        await fileSink.flush();
        await fileSink.close();
      }

      _showSnackBar(
        '${selectedList.length} şarkı başarıyla indirildi!',
        isError: false,
      );
    } catch (e) {
      _showSnackBar('İndirme hatası: ${e.toString()}', isError: true);
    } finally {
      setState(() {
        _isDownloading = false;
        _currentDownload = '';
      });
    }
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  List<Video> get _filteredVideos {
    if (_searchQuery.isEmpty) return _videos;
    return _videos
        .where(
          (v) => v.title.toLowerCase().contains(_searchQuery.toLowerCase()),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("YouTube Playlist İndirici"),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_videos.isNotEmpty)
            PopupMenuButton<String>(
              onSelected: (value) {
                setState(() {
                  if (value == 'select_all') {
                    _selected.addAll(_filteredVideos);
                  } else if (value == 'deselect_all') {
                    _selected.clear();
                  } else if (value == 'invert_selection') {
                    final current = Set<Video>.from(_selected);
                    _selected.clear();
                    for (var video in _filteredVideos) {
                      if (!current.contains(video)) {
                        _selected.add(video);
                      }
                    }
                  }
                });
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'select_all',
                  child: Row(
                    children: [
                      Icon(Icons.select_all),
                      SizedBox(width: 8),
                      Text('Tümünü Seç'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'deselect_all',
                  child: Row(
                    children: [
                      Icon(Icons.deselect),
                      SizedBox(width: 8),
                      Text('Seçimi Kaldır'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'invert_selection',
                  child: Row(
                    children: [
                      Icon(Icons.flip_to_back),
                      SizedBox(width: 8),
                      Text('Seçimi Ters Çevir'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        labelText: 'YouTube Playlist URL',
                        hintText: 'https://www.youtube.com/playlist?list=...',
                        prefixIcon: const Icon(Icons.link),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        suffixIcon: _controller.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _controller.clear();
                                  setState(() {});
                                },
                              )
                            : null,
                      ),
                      onChanged: (value) => setState(() {}),
                      onSubmitted: (_) => _fetchPlaylist(),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isLoading ? null : _fetchPlaylist,
                        icon: _isLoading
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimary,
                                ),
                              )
                            : const Icon(Icons.download),
                        label: Text(
                          _isLoading ? 'Yükleniyor...' : 'Playlist Yükle',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_videos.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextField(
                        decoration: InputDecoration(
                          labelText: 'Şarkı Ara',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _searchQuery = value;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${_selected.length}/${_filteredVideos.length} şarkı seçili',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          if (_isDownloading)
                            Text(
                              '${(_progress * 100).toStringAsFixed(1)}%',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                            ),
                        ],
                      ),
                      if (_isDownloading) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: _progress,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'İndiriliyor: $_currentDownload',
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Expanded(
              child: _isLoading
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedBuilder(
                            animation: _loadingController,
                            builder: (context, child) {
                              return Transform.rotate(
                                angle: _loadingController.value * 2 * pi,
                                child: const Icon(Icons.refresh, size: 48),
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Playlist yükleniyor...',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                    )
                  : _videos.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.playlist_play,
                            size: 64,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Henüz playlist yüklenmedi',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Yukarıdan bir YouTube playlist linki girin',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        Expanded(
                          child: ReorderableListView.builder(
                            itemCount: _filteredVideos.length,
                            onReorder: (oldIndex, newIndex) {
                              setState(() {
                                if (newIndex > oldIndex) newIndex--;
                                final item = _videos.removeAt(oldIndex);
                                _videos.insert(newIndex, item);
                              });
                            },
                            itemBuilder: (context, index) {
                              final video = _filteredVideos[index];
                              final isSelected = _selected.contains(video);

                              return Card(
                                key: ValueKey(video.id.value),
                                margin: const EdgeInsets.only(bottom: 8),
                                child: CheckboxListTile(
                                  value: isSelected,
                                  onChanged: (val) {
                                    setState(() {
                                      if (val == true) {
                                        _selected.add(video);
                                      } else {
                                        _selected.remove(video);
                                      }
                                    });
                                  },
                                  secondary: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      video.thumbnails.mediumResUrl,
                                      width: 60,
                                      height: 45,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                            return Container(
                                              width: 60,
                                              height: 45,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.surfaceVariant,
                                              child: const Icon(
                                                Icons.music_note,
                                              ),
                                            );
                                          },
                                    ),
                                  ),
                                  title: Text(
                                    video.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        video.author,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.outline,
                                            ),
                                      ),
                                      Text(
                                        video.duration?.toString() ??
                                            "Bilinmiyor",
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                            ),
                                      ),
                                    ],
                                  ),
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                ),
                              );
                            },
                          ),
                        ),
                        if (_selected.isNotEmpty && !_isDownloading)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _downloadSelected,
                                icon: const Icon(Icons.download),
                                label: Text(
                                  '${_selected.length} Şarkıyı İndir',
                                ),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.all(16),
                                ),
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
}

// ---------------- DOWNLOADED FILES TAB ----------------
class DownloadedFiles extends StatefulWidget {
  final AudioPlayer audioPlayer;
  const DownloadedFiles({super.key, required this.audioPlayer});

  @override
  State<DownloadedFiles> createState() => _DownloadedFilesState();
}

class _DownloadedFilesState extends State<DownloadedFiles> {
  List<FileSystemEntity> _files = [];
  String _searchQuery = '';
  String _sortBy = 'name'; // name, date, size

  Future<void> _loadFiles() async {
    var dir = await getApplicationDocumentsDirectory();
    var files = Directory(
      dir.path,
    ).listSync().where((f) => f.path.endsWith(".mp3")).toList();

    // Sıralama
    files.sort((a, b) {
      switch (_sortBy) {
        case 'date':
          return b.statSync().modified.compareTo(a.statSync().modified);
        case 'size':
          return b.statSync().size.compareTo(a.statSync().size);
        default:
          return a.path.split('/').last.compareTo(b.path.split('/').last);
      }
    });

    setState(() {
      _files = files;
    });
  }

  List<FileSystemEntity> get _filteredFiles {
    if (_searchQuery.isEmpty) return _files;
    return _files
        .where(
          (f) => f.path
              .split('/')
              .last
              .toLowerCase()
              .contains(_searchQuery.toLowerCase()),
        )
        .toList();
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _deleteFile(FileSystemEntity file) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dosyayı Sil'),
        content: Text(
          '${file.path.split('/').last} dosyasını silmek istediğinizden emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (result == true) {
      await file.delete();
      _loadFiles();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dosya silindi'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("İndirilen Şarkılar"),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() {
                _sortBy = value;
              });
              _loadFiles();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'name',
                child: Row(
                  children: [
                    Icon(_sortBy == 'name' ? Icons.check : Icons.sort_by_alpha),
                    const SizedBox(width: 8),
                    const Text('İsme Göre'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'date',
                child: Row(
                  children: [
                    Icon(_sortBy == 'date' ? Icons.check : Icons.access_time),
                    const SizedBox(width: 8),
                    const Text('Tarihe Göre'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'size',
                child: Row(
                  children: [
                    Icon(_sortBy == 'size' ? Icons.check : Icons.storage),
                    const SizedBox(width: 8),
                    const Text('Boyuta Göre'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                labelText: 'Şarkı Ara',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),
          if (_files.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    '${_filteredFiles.length} şarkı',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  Text(
                    'Toplam: ${_formatFileSize(_files.fold<int>(0, (sum, file) => sum + file.statSync().size))}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _files.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.music_off,
                          size: 64,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Henüz indirilen şarkı yok',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadFiles,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _filteredFiles.length,
                      itemBuilder: (context, index) {
                        var file = _filteredFiles[index];
                        var fileName = file.path.split('/').last;
                        var stat = file.statSync();

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primaryContainer,
                              child: Icon(
                                Icons.music_note,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                              ),
                            ),
                            title: Text(
                              fileName.replaceAll('.mp3', ''),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_formatFileSize(stat.size)),
                                Text(
                                  '${stat.modified.day}/${stat.modified.month}/${stat.modified.year}',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.outline,
                                      ),
                                ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.play_arrow),
                                  onPressed: () async {
                                    try {
                                      await widget.audioPlayer.setFilePath(
                                        file.path,
                                      );
                                      widget.audioPlayer.play();
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Oynatılıyor: ${fileName.replaceAll('.mp3', '')}',
                                          ),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    } catch (e) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text('Oynatma hatası: $e'),
                                          backgroundColor: Colors.red,
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    }
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _deleteFile(file),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------- AUDIO PLAYER TAB ----------------
class AudioPlayerPage extends StatefulWidget {
  final AudioPlayer audioPlayer;
  const AudioPlayerPage({super.key, required this.audioPlayer});

  @override
  State<AudioPlayerPage> createState() => _AudioPlayerPageState();
}

class _AudioPlayerPageState extends State<AudioPlayerPage>
    with TickerProviderStateMixin {
  late AnimationController _rotationController;
  late AnimationController _scaleController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    );
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    widget.audioPlayer.playerStateStream.listen((state) {
      if (state.playing) {
        _rotationController.repeat();
      } else {
        _rotationController.stop();
      }
    });
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '0:00';
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Müzik Oynatıcı"),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: StreamBuilder<PlayerState>(
        stream: widget.audioPlayer.playerStateStream,
        builder: (context, snapshot) {
          final state = snapshot.data;
          final playing = state?.playing ?? false;
          final processingState =
              state?.processingState ?? ProcessingState.idle;

          return SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Column(
                      // içerik taşarsa alttan boşluk yerine kaydır
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // ÜST KISIM
                        Column(
                          children: [
                            // Albüm kapağı animasyonu
                            AnimatedBuilder(
                              animation: _rotationController,
                              builder: (context, child) {
                                return Transform.rotate(
                                  angle: _rotationController.value * 2 * pi,
                                  child: Container(
                                    width: 200,
                                    height: 200,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        colors: [
                                          Theme.of(context).colorScheme.primary,
                                          Theme.of(
                                            context,
                                          ).colorScheme.secondary,
                                        ],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary
                                              .withOpacity(0.3),
                                          blurRadius: 20,
                                          spreadRadius: 5,
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      Icons.music_note,
                                      size: 80,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onPrimary,
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 28),

                            // Şarkı bilgisi
                            StreamBuilder<SequenceState?>(
                              stream: widget.audioPlayer.sequenceStateStream,
                              builder: (context, snapshot) {
                                final currentSource =
                                    snapshot.data?.currentSource;
                                final title =
                                    currentSource?.tag?.title ??
                                    'Şarkı seçilmedi';

                                return Column(
                                  children: [
                                    Text(
                                      title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Bilinmeyen Sanatçı',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.outline,
                                          ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 24),

                            // İlerleme çubuğu
                            StreamBuilder<Duration>(
                              stream: widget.audioPlayer.positionStream,
                              builder: (context, snapshot) {
                                final position = snapshot.data ?? Duration.zero;
                                final duration =
                                    widget.audioPlayer.duration ??
                                    Duration.zero;

                                final totalMs = duration.inMilliseconds;
                                final posMs = position.inMilliseconds.clamp(
                                  0,
                                  totalMs,
                                );

                                return Column(
                                  children: [
                                    Slider(
                                      min: 0,
                                      max: totalMs > 0 ? totalMs.toDouble() : 1,
                                      value: totalMs > 0 ? posMs.toDouble() : 0,
                                      onChanged: totalMs > 0
                                          ? (value) => widget.audioPlayer.seek(
                                              Duration(
                                                milliseconds: value.round(),
                                              ),
                                            )
                                          : null,
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            _formatDuration(
                                              Duration(milliseconds: posMs),
                                            ),
                                          ),
                                          Text(_formatDuration(duration)),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // KONTROLLER (ALT KISIM)
                        Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.skip_previous),
                                  iconSize: 40,
                                  onPressed: () {
                                    // Önceki şarkı
                                    widget.audioPlayer.seekToPrevious();
                                  },
                                ),
                                GestureDetector(
                                  onTapDown: (_) => _scaleController.forward(),
                                  onTapUp: (_) => _scaleController.reverse(),
                                  onTapCancel: () => _scaleController.reverse(),
                                  child: AnimatedBuilder(
                                    animation: _scaleController,
                                    builder: (context, child) {
                                      return Transform.scale(
                                        scale:
                                            1.0 -
                                            (_scaleController.value * 0.1),
                                        child: Container(
                                          width: 80,
                                          height: 80,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary
                                                    .withOpacity(0.3),
                                                blurRadius: 15,
                                                spreadRadius: 2,
                                              ),
                                            ],
                                          ),
                                          child: IconButton(
                                            icon: Icon(
                                              processingState ==
                                                      ProcessingState.loading
                                                  ? Icons.hourglass_empty
                                                  : playing
                                                  ? Icons.pause
                                                  : Icons.play_arrow,
                                              size: 40,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onPrimary,
                                            ),
                                            onPressed: () {
                                              if (processingState ==
                                                  ProcessingState.loading)
                                                return;
                                              playing
                                                  ? widget.audioPlayer.pause()
                                                  : widget.audioPlayer.play();
                                            },
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.skip_next),
                                  iconSize: 40,
                                  onPressed: () {
                                    // Sonraki şarkı
                                    widget.audioPlayer.seekToNext();
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.shuffle),
                                  onPressed: () async {
                                    final enabled = !(await widget
                                        .audioPlayer
                                        .shuffleModeEnabled);
                                    await widget.audioPlayer
                                        .setShuffleModeEnabled(enabled);
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.repeat),
                                  onPressed: () async {
                                    final mode =
                                        await widget.audioPlayer.loopMode ==
                                            LoopMode.off
                                        ? LoopMode.all
                                        : LoopMode.off;
                                    await widget.audioPlayer.setLoopMode(mode);
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.stop),
                                  onPressed: () => widget.audioPlayer.stop(),
                                ),
                              ],
                            ),
                            SizedBox(
                              height: MediaQuery.of(context).padding.bottom + 8,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// ---------------- SETTINGS PAGE ----------------
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _darkMode = false;
  String _downloadQuality = 'high';
  bool _autoPlay = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _darkMode = prefs.getBool('dark_mode') ?? false;
      _downloadQuality = prefs.getString('download_quality') ?? 'high';
      _autoPlay = prefs.getBool('auto_play') ?? false;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', _darkMode);
    await prefs.setString('download_quality', _downloadQuality);
    await prefs.setBool('auto_play', _autoPlay);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Ayarlar"),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Görünüm',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Karanlık Tema'),
                    subtitle: const Text('Uygulamayı karanlık temada kullan'),
                    value: _darkMode,
                    onChanged: (value) {
                      setState(() {
                        _darkMode = value;
                      });
                      _saveSettings();
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'İndirme Ayarları',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    title: const Text('İndirme Kalitesi'),
                    subtitle: Text(
                      _downloadQuality == 'high'
                          ? 'Yüksek Kalite'
                          : 'Orta Kalite',
                    ),
                    trailing: DropdownButton<String>(
                      value: _downloadQuality,
                      items: const [
                        DropdownMenuItem(value: 'high', child: Text('Yüksek')),
                        DropdownMenuItem(value: 'medium', child: Text('Orta')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _downloadQuality = value!;
                        });
                        _saveSettings();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Oynatıcı Ayarları',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Otomatik Oynat'),
                    subtitle: const Text(
                      'Şarkı seçildiğinde otomatik olarak oynat',
                    ),
                    value: _autoPlay,
                    onChanged: (value) {
                      setState(() {
                        _autoPlay = value;
                      });
                      _saveSettings();
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hakkında',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  const ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('Versiyon'),
                    subtitle: Text('1.0.0'),
                  ),
                  const ListTile(
                    leading: Icon(Icons.developer_mode),
                    title: Text('Geliştirici'),
                    subtitle: Text('Mehmet Çayır'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.star_outline),
                    title: const Text('Uygulamayı Değerlendir'),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Değerlendirme özelliği yakında eklenecek!',
                          ),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
