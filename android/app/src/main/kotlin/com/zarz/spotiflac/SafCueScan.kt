package com.zarz.spotiflac

import androidx.documentfile.provider.DocumentFile
import java.io.File
import java.util.Locale

// CUE sheet helpers for the SAF library scan: the audio file a sheet names,
// cached per-directory child lookups, and resolving the sheet's audio sibling.

    /**
     * Extract the audio filename referenced by a CUE sheet file.
     * Reads the FILE "name" TYPE line from the .cue text.
     * Returns just the filename (no path), or null if not found.
     */
internal fun MainActivity.extractCueAudioFileName(cueTempPath: String): String? {
        try {
            val lines = File(cueTempPath).readLines()
            for (line in lines) {
                val trimmed = line.trim().let { l ->
                    if (l.startsWith("\uFEFF")) l.removePrefix("\uFEFF").trim() else l
                }
                if (trimmed.uppercase(Locale.ROOT).startsWith("FILE ")) {
                    val rest = trimmed.substring(5).trim()
                    val filename = if (rest.startsWith("\"")) {
                        val endQuote = rest.indexOf('"', 1)
                        if (endQuote > 0) rest.substring(1, endQuote) else rest
                    } else {
                        val parts = rest.split("\\s+".toRegex())
                        if (parts.size >= 2) parts.dropLast(1).joinToString(" ") else rest
                    }
                    return filename.substringAfterLast("/").substringAfterLast("\\")
                }
            }
        } catch (e: Exception) {
            android.util.Log.w("SpotiFLAC", "Failed to extract audio filename from CUE: ${e.message}")
        }
        return null
    }

    private val cueSiblingAudioExtensions = listOf(
        ".flac", ".wav", ".ape", ".mp3", ".ogg", ".wv", ".m4a", ".mp4", ".aac"
    )

internal fun MainActivity.getSafChildFileLookup(
        dir: DocumentFile,
        cache: MutableMap<String, Map<String, DocumentFile>>,
    ): Map<String, DocumentFile> {
        val dirKey = dir.uri.toString()
        return cache.getOrPut(dirKey) { safChildFileLookup(listSafChildrenOrThrow(dir)) }
    }

private fun safChildFileLookup(children: List<SafChildEntry>): Map<String, DocumentFile> =
    buildMap {
        for (child in children) {
            if (child.isDirectory) continue
            val childName = child.name?.trim().orEmpty()
            if (childName.isBlank()) continue
            put(childName.lowercase(Locale.ROOT), child.doc)
        }
    }

/** Keeps a traversal listing for CUE sibling lookup so the directory is not
 * queried again; on network providers every listing is a round trip. */
internal fun rememberCueDirectoryListing(
    dir: DocumentFile,
    children: List<SafChildEntry>,
    cache: MutableMap<String, Map<String, DocumentFile>>,
) {
    if (children.any { !it.isDirectory && it.name?.endsWith(".cue", ignoreCase = true) == true }) {
        cache[dir.uri.toString()] = safChildFileLookup(children)
    }
}

internal fun MainActivity.resolveCueAudioSibling(
        parentDir: DocumentFile,
        cueName: String,
        audioFileName: String?,
        childLookupCache: MutableMap<String, Map<String, DocumentFile>>,
    ): DocumentFile? {
        val childLookup = getSafChildFileLookup(parentDir, childLookupCache)

        val directMatch = audioFileName
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?.substringAfterLast("/")
            ?.substringAfterLast("\\")
            ?.lowercase(Locale.ROOT)
            ?.let(childLookup::get)
        if (directMatch != null) {
            return directMatch
        }

        val cueBaseName = cueName.substringBeforeLast('.').trim()
        if (cueBaseName.isBlank()) {
            return null
        }

        val cueBaseKey = cueBaseName.lowercase(Locale.ROOT)
        for (ext in cueSiblingAudioExtensions) {
            childLookup["$cueBaseKey$ext"]?.let { return it }
        }
        return null
    }
