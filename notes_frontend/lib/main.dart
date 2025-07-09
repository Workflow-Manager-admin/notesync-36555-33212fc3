import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

// PUBLIC_INTERFACE
void main() {
  runApp(const NotesApp());
}

/// PUBLIC_INTERFACE
/// Main root widget for the Notes Application.
class NotesApp extends StatelessWidget {
  const NotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Notes",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        primaryColor: const Color(0xFF1976D2),
        colorScheme: ColorScheme.light(
          primary: const Color(0xFF1976D2),
          onPrimary: Colors.white,
          secondary: const Color(0xFF424242),
          onSecondary: Colors.white,
          surface: Colors.white,
          error: Colors.red,
          onError: Colors.white,
          onSurface: Colors.black87,
        ),
        scaffoldBackgroundColor: Colors.white,
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFFFFC107),
          foregroundColor: Colors.black,
          elevation: 3,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1976D2),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF1976D2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF1976D2), width: 2),
          ),
        ),
      ),
      home: const NotesHomePage(),
    );
  }
}

/// Note data model.
class Note {
  int? id;
  String title;
  String content;
  DateTime updatedAt;
  List<String> tags;
  String? category;

  Note({
    this.id,
    required this.title,
    required this.content,
    required this.updatedAt,
    required this.tags,
    this.category,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'updated_at': updatedAt.toIso8601String(),
      'tags': tags.join(','),
      'category': category ?? '',
    };
  }

  static Note fromMap(Map<String, dynamic> map) {
    return Note(
      id: map['id'] as int?,
      title: map['title'] as String,
      content: map['content'] as String,
      updatedAt: DateTime.parse(map['updated_at']),
      tags: (map['tags'] as String).isNotEmpty
          ? (map['tags'] as String).split(',').map((t) => t.trim()).toList()
          : [],
      category: (map['category'] as String).isNotEmpty ? map['category'] as String : null,
    );
  }
}

/// Local DB helper for notes storage and sync.
class NotesDBHelper {
  static final NotesDBHelper _singleton = NotesDBHelper._internal();
  Database? _database;

  factory NotesDBHelper() => _singleton;

  NotesDBHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    // Initialize db.
    WidgetsFlutterBinding.ensureInitialized();
    final dbPath = path.join(await getDatabasesPath(), 'notes.db');
    _database = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE notes(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT,
            content TEXT,
            updated_at TEXT,
            tags TEXT,
            category TEXT
          )
        ''');
      },
    );
    return _database!;
  }

  // PUBLIC_INTERFACE
  Future<List<Note>> getAllNotes({String? search, String? category, String? tag}) async {
    final db = await database;
    var whereList = <String>[];
    var whereArgs = <dynamic>[];

    if (search != null && search.isNotEmpty) {
      whereList.add('(title LIKE ? OR content LIKE ?)');
      whereArgs.add('%$search%');
      whereArgs.add('%$search%');
    }
    if (category != null && category.isNotEmpty) {
      whereList.add('category = ?');
      whereArgs.add(category);
    }
    if (tag != null && tag.isNotEmpty) {
      whereList.add("tags LIKE ?");
      whereArgs.add('%$tag%');
    }

    final whereStr = whereList.isNotEmpty ? whereList.join(' AND ') : null;
    final query = await db.query(
      'notes',
      orderBy: 'updated_at DESC',
      where: whereStr,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
    );

    return query.map((row) => Note.fromMap(row)).toList();
  }

  // PUBLIC_INTERFACE
  Future<int> addNote(Note note) async {
    final db = await database;
    return await db.insert('notes', note.toMap());
  }

  // PUBLIC_INTERFACE
  Future<int> updateNote(Note note) async {
    final db = await database;
    return await db.update(
      'notes',
      note.toMap(),
      where: 'id = ?',
      whereArgs: [note.id],
    );
  }

  // PUBLIC_INTERFACE
  Future<int> deleteNote(int id) async {
    final db = await database;
    return await db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }

  // PUBLIC_INTERFACE
  Future<List<String>> getAllCategories() async {
    final db = await database;
    final res = await db.rawQuery('SELECT DISTINCT category FROM notes WHERE category IS NOT NULL AND category != ""');
    return res.map<String>((row) => row['category'] as String).toList();
  }

  // PUBLIC_INTERFACE
  Future<List<String>> getAllTags() async {
    final db = await database;
    final res = await db.rawQuery('SELECT tags FROM notes');
    final tags = <String>{};
    for (var row in res) {
      final tagsStr = row['tags'] as String;
      if (tagsStr.isNotEmpty) {
        tags.addAll(tagsStr.split(',').map((e) => e.trim()));
      }
    }
    return tags.where((t) => t.isNotEmpty).toList();
  }
}

/// HomePage for displaying, searching, and organizing notes.
class NotesHomePage extends StatefulWidget {
  const NotesHomePage({super.key});

  @override
  State<NotesHomePage> createState() => _NotesHomePageState();
}

enum NoteViewMode { list, grid }

class _NotesHomePageState extends State<NotesHomePage> {
  String? searchKeyword;
  String? selectedCategory;
  String? selectedTag;
  NoteViewMode viewMode = NoteViewMode.list;

  late Future<List<Note>> notesFuture;

  List<String> categories = [];
  List<String> tags = [];

  @override
  void initState() {
    super.initState();
    _refresh();
    _refreshCategoriesTags();
  }

  void _refresh() {
    setState(() {
      notesFuture = NotesDBHelper().getAllNotes(
        search: searchKeyword,
        category: selectedCategory,
        tag: selectedTag,
      );
    });
  }

  void _refreshCategoriesTags() async {
    categories = await NotesDBHelper().getAllCategories();
    tags = await NotesDBHelper().getAllTags();
    setState(() {});
  }

  void _clearFilters() {
    setState(() {
      searchKeyword = null;
      selectedCategory = null;
      selectedTag = null;
      _refresh();
    });
  }

  void _updateViewMode() {
    setState(() {
      viewMode = viewMode == NoteViewMode.list ? NoteViewMode.grid : NoteViewMode.list;
    });
  }

  void _openNoteDetail({Note? note}) async {
    // Now, using only BuildContext (no shadowed Context)
    final bool updated = await Navigator.of(context)
        .push(MaterialPageRoute(builder: (BuildContext context) => NoteDetailPage(existingNote: note)));
    if (updated == true) {
      _refresh();
      _refreshCategoriesTags();
    }
  }

  void _deleteNote(int noteId) async {
    await NotesDBHelper().deleteNote(noteId);
    _refresh();
    _refreshCategoriesTags();
  }

  @override
  Widget build(BuildContext context) {
    final isAnyFilter = searchKeyword?.isNotEmpty == true ||
        selectedCategory?.isNotEmpty == true ||
        selectedTag?.isNotEmpty == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Notes"),
        actions: [
          if (isAnyFilter)
            IconButton(
              onPressed: _clearFilters,
              icon: const Icon(Icons.filter_alt_off_outlined),
              tooltip: "Clear filters",
            ),
          IconButton(
            onPressed: _updateViewMode,
            icon: Icon(
              viewMode == NoteViewMode.list ? Icons.grid_view : Icons.list,
            ),
            tooltip: viewMode == NoteViewMode.list ? "Grid View" : "List View",
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.only(top: 4.0, left: 8.0, right: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Search Field
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: "Search notes...",
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onChanged: (q) {
                  setState(() {
                    searchKeyword = q.isNotEmpty ? q : null;
                    _refresh();
                  });
                },
              ),
            ),
            // Categories/Tags Row
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (categories.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 2),
                      child: Text("Categories:", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    ...categories.map((c) => ChoiceChip(
                          label: Text(c),
                          selected: selectedCategory == c,
                          onSelected: (v) {
                            setState(() {
                              selectedCategory = v ? c : null;
                              selectedTag = null;
                              _refresh();
                            });
                          },
                        )),
                  ],
                  if (tags.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 2),
                      child: Text("Tags:", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    ...tags.map((t) => ChoiceChip(
                          label: Text("#$t"),
                          selected: selectedTag == t,
                          onSelected: (v) {
                            setState(() {
                              selectedTag = v ? t : null;
                              selectedCategory = null;
                              _refresh();
                            });
                          },
                        )),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Notes List/Grid
            Expanded(
              child: FutureBuilder<List<Note>>(
                future: notesFuture,
                builder: (BuildContext context, AsyncSnapshot<List<Note>> snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text("Failed to load notes."));
                  }
                  final notes = snapshot.data ?? [];
                  if (notes.isEmpty) {
                    return const Center(
                        child: Text(
                      "No notes found.",
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.black54,
                      ),
                    ));
                  }
                  if (viewMode == NoteViewMode.grid) {
                    return GridView.builder(
                      itemCount: notes.length,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 1.1,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemBuilder: (BuildContext context, int idx) => NoteCard(
                        note: notes[idx],
                        onTap: () => _openNoteDetail(note: notes[idx]),
                        onDelete: () => _deleteNote(notes[idx].id!),
                      ),
                    );
                  }
                  // List view
                  return ListView.builder(
                    itemCount: notes.length,
                    itemBuilder: (BuildContext context, int idx) => NoteListTile(
                      note: notes[idx],
                      onTap: () => _openNoteDetail(note: notes[idx]),
                      onDelete: () => _deleteNote(notes[idx].id!),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: "New Note",
        onPressed: () => _openNoteDetail(),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 6,
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// Widget for a note in the grid view.
class NoteCard extends StatelessWidget {
  final Note note;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  // Use super.key shortcut in constructor
  const NoteCard({
    super.key,
    required this.note,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final tagWidgets = note.tags.take(2).map((t) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2.0),
          child: Chip(
            label: Text("#$t", style: const TextStyle(fontSize: 11)),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ));

    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 1,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                note.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium!
                    .copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                note.content,
                maxLines: 4,
                style: const TextStyle(fontSize: 13, color: Colors.black87),
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: tagWidgets.toList()),
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                  ),
                ],
              ),
              if ((note.category ?? "").isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2.0),
                  child: Text(
                    note.category!,
                    style: const TextStyle(
                        color: Color(0xFF1976D2), fontSize: 12, fontStyle: FontStyle.italic),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Widget for a note in the list view.
class NoteListTile extends StatelessWidget {
  final Note note;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  // Use super.key shortcut in constructor
  const NoteListTile({
    super.key,
    required this.note,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final tagTexts = note.tags.map((t) => "#$t").join('  ');
    return Card(
      elevation: 0.5,
      margin: const EdgeInsets.symmetric(vertical: 5),
      color: Colors.white,
      child: ListTile(
        title: Text(note.title,
            style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              note.content,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Wrap(
              spacing: 5,
              children: [
                if (note.category?.isNotEmpty == true)
                  Chip(
                      label: Text(note.category!, style: const TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: Theme.of(context).primaryColor.withAlpha(25),
                  ),
                if (note.tags.isNotEmpty)
                  Text(tagTexts, style: const TextStyle(fontSize: 11, color: Colors.black54)),
              ],
            ),
            Text(
              'Updated: ${_formatDate(note.updatedAt)}',
              style: const TextStyle(fontSize: 11, color: Colors.black45),
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
          onPressed: onDelete,
        ),
        onTap: onTap,
      ),
    );
  }
}

String _formatDate(DateTime dt) {
  final now = DateTime.now();
  if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
    return "Today, ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }
  return "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}";
}

/// Page for creating or editing a note.
class NoteDetailPage extends StatefulWidget {
  final Note? existingNote;

  const NoteDetailPage({super.key, this.existingNote});

  @override
  State<NoteDetailPage> createState() => _NoteDetailPageState();
}

class _NoteDetailPageState extends State<NoteDetailPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleCtl;
  late TextEditingController _contentCtl;
  late TextEditingController _tagsCtl;
  late TextEditingController _categoryCtl;

  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleCtl = TextEditingController(text: widget.existingNote?.title ?? '');
    _contentCtl = TextEditingController(text: widget.existingNote?.content ?? '');
    _tagsCtl = TextEditingController(
        text: widget.existingNote?.tags.join(', ') ?? '');
    _categoryCtl =
        TextEditingController(text: widget.existingNote?.category ?? "");
  }

  @override
  void dispose() {
    _titleCtl.dispose();
    _contentCtl.dispose();
    _tagsCtl.dispose();
    _categoryCtl.dispose();
    super.dispose();
  }

  // PUBLIC_INTERFACE
  Future<void> _saveNote() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isSaving = true);

    final tagsList = _tagsCtl.text.split(',').map((e) => e.trim()).where((s) => s.isNotEmpty).toList();
    final newNote = Note(
      id: widget.existingNote?.id,
      title: _titleCtl.text.trim(),
      content: _contentCtl.text.trim(),
      updatedAt: DateTime.now(),
      tags: tagsList,
      category: _categoryCtl.text.trim().isNotEmpty ? _categoryCtl.text.trim() : null,
    );
    if (widget.existingNote == null) {
      await NotesDBHelper().addNote(newNote);
    } else {
      await NotesDBHelper().updateNote(newNote);
    }
    Navigator.of(context).pop(true);
  }

  Future<void> _deleteNote() async {
    if (widget.existingNote?.id != null) {
      await NotesDBHelper().deleteNote(widget.existingNote!.id!);
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingNote != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Note' : 'New Note'),
        actions: [
          if (isEditing)
            IconButton(
              tooltip: "Delete Note",
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: isSaving ? null : _deleteNote,
            ),
          IconButton(
            tooltip: "Save",
            icon: const Icon(Icons.check),
            onPressed: isSaving ? null : _saveNote,
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: isSaving,
        child: Padding(
          padding: const EdgeInsets.only(left: 16, right: 16, top: 18, bottom: 8),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                // Title
                TextFormField(
                  controller: _titleCtl,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    prefixIcon: Icon(Icons.title_outlined),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? "Title required" : null,
                  textInputAction: TextInputAction.next,
                  autofocus: !isEditing,
                ),
                const SizedBox(height: 18),
                // Content
                TextFormField(
                  controller: _contentCtl,
                  style: const TextStyle(fontSize: 15),
                  decoration: const InputDecoration(
                    labelText: 'Content',
                    prefixIcon: Icon(Icons.description_outlined),
                  ),
                  minLines: 6,
                  maxLines: null,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? "Note content required" : null,
                  keyboardType: TextInputType.multiline,
                ),
                const SizedBox(height: 18),
                // Tags
                TextFormField(
                  controller: _tagsCtl,
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                    labelText: 'Tags (comma-separated)',
                    prefixIcon: Icon(Icons.tag_outlined),
                  ),
                  keyboardType: TextInputType.text,
                ),
                const SizedBox(height: 18),
                // Category
                TextFormField(
                  controller: _categoryCtl,
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                    labelText: 'Category (optional)',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  keyboardType: TextInputType.text,
                ),
                const SizedBox(height: 24),
                if (isSaving)
                  const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
