import 'dart:io';
import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Playlist MP3 Downloader',
      theme: ThemeData(primarySwatch: Colors.red),
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

class _HomeTabsState extends State<HomeTabs> {
  int _currentIndex = 0;
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  Widget build(BuildContext context) {
    final tabs = [
      PlaylistDownloader(audioPlayer: _audioPlayer),
      DownloadedFiles(audioPlayer: _audioPlayer),
      AudioPlayerPage(audioPlayer: _audioPlayer),
    ];

    return Scaffold(
      body: tabs[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.playlist_play),
            label: "Playlist",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.download),
            label: "İndirilenler",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.music_note),
            label: "Oynatıcı",
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

class _PlaylistDownloaderState extends State<PlaylistDownloader> {
  final _yt = YoutubeExplode();
  final _controller = TextEditingController();
  List<Video> _videos = [];
  Set<Video> _selected = {};
  bool _isLoading = false;
  double _progress = 0.0;
  bool _isDownloading = false;

  Future<void> _fetchPlaylist() async {
    setState(() {
      _isLoading = true;
      _videos.clear();
      _selected.clear();
    });

    try {
      var playlist = await _yt.playlists.get(_controller.text);
      var videos = await _yt.playlists.getVideos(playlist.id).toList();

      setState(() {
        _videos = videos;
        _selected.addAll(videos); // Başta hepsi seçili
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Playlist yüklenirken hata: $e")));
    }
  }

  Future<void> _downloadSelected() async {
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Hiç şarkı seçmediniz!")));
      return;
    }

    await Permission.storage.request();
    setState(() {
      _isDownloading = true;
      _progress = 0.0;
    });

    var dir = await getApplicationDocumentsDirectory();
    var selectedList = _selected.toList();

    for (int i = 0; i < selectedList.length; i++) {
      var v = selectedList[i];
      var manifest = await _yt.videos.streamsClient.getManifest(v.id);
      var audioStreamInfo = manifest.audioOnly.withHighestBitrate();
      var audioStream = _yt.videos.streamsClient.get(audioStreamInfo);

      var safeTitle = v.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      var filePath = '${dir.path}/$safeTitle.mp3';
      var file = File(filePath);
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

    setState(() => _isDownloading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Seçilen şarkılar indirildi!')),
    );
  }

  @override
  void dispose() {
    _yt.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Playlist Düzenleme"),
        actions: [
          if (_videos.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.select_all),
              onPressed: () {
                setState(() {
                  if (_selected.length == _videos.length) {
                    _selected.clear();
                  } else {
                    _selected.addAll(_videos);
                  }
                });
              },
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'YouTube Playlist Linki',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _fetchPlaylist,
              child: const Text("Listeyi Getir"),
            ),
            const SizedBox(height: 8),
            _isLoading
                ? const CircularProgressIndicator()
                : _videos.isEmpty
                ? const Text("Henüz playlist yok")
                : Expanded(
                    child: ReorderableListView(
                      onReorder: (oldIndex, newIndex) {
                        setState(() {
                          if (newIndex > oldIndex) newIndex--;
                          final item = _videos.removeAt(oldIndex);
                          _videos.insert(newIndex, item);
                        });
                      },
                      children: [
                        for (final v in _videos)
                          GestureDetector(
                            onLongPress: () {
                              setState(() {
                                _videos.remove(v);
                                _selected.remove(v);
                              });
                            },
                            child: CheckboxListTile(
                              key: ValueKey(v.id.value),
                              value: _selected.contains(v),
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    _selected.add(v);
                                  } else {
                                    _selected.remove(v);
                                  }
                                });
                              },
                              secondary: Image.network(v.thumbnails.highResUrl),
                              title: Text(
                                v.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(v.duration?.toString() ?? ""),
                              controlAffinity: ListTileControlAffinity.leading,
                            ),
                          ),
                      ],
                    ),
                  ),
            if (_isDownloading)
              Column(
                children: [
                  LinearProgressIndicator(value: _progress),
                  Text(
                    "İndirme Durumu: ${(_progress * 100).toStringAsFixed(1)}%",
                  ),
                ],
              ),
            if (_videos.isNotEmpty && !_isDownloading)
              ElevatedButton.icon(
                onPressed: _downloadSelected,
                icon: const Icon(Icons.download),
                label: const Text("Seçilenleri İndir"),
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

  Future<void> _loadFiles() async {
    var dir = await getApplicationDocumentsDirectory();
    setState(() {
      _files = Directory(
        dir.path,
      ).listSync().where((f) => f.path.endsWith(".mp3")).toList();
    });
  }

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("İndirilenler")),
      body: RefreshIndicator(
        onRefresh: () async => _loadFiles(),
        child: ListView.builder(
          itemCount: _files.length,
          itemBuilder: (context, index) {
            var file = _files[index];
            return ListTile(
              title: Text(file.path.split('/').last),
              trailing: IconButton(
                icon: const Icon(Icons.play_arrow),
                onPressed: () async {
                  await widget.audioPlayer.setFilePath(file.path);
                  widget.audioPlayer.play();
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

// ---------------- AUDIO PLAYER TAB ----------------
class AudioPlayerPage extends StatelessWidget {
  final AudioPlayer audioPlayer;
  const AudioPlayerPage({super.key, required this.audioPlayer});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Oynatıcı")),
      body: Center(
        child: StreamBuilder<PlayerState>(
          stream: audioPlayer.playerStateStream,
          builder: (context, snapshot) {
            final state = snapshot.data;
            final playing = state?.playing ?? false;
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(
                    playing ? Icons.pause : Icons.play_arrow,
                    size: 50,
                  ),
                  onPressed: () {
                    playing ? audioPlayer.pause() : audioPlayer.play();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.stop, size: 50),
                  onPressed: () => audioPlayer.stop(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
