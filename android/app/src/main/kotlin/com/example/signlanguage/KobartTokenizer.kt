package com.example.signlanguage

import org.json.JSONObject
import java.text.Normalizer

/** NFKC, Metaspace and BPE as configured in the supplied tokenizer.json. */
internal class KobartTokenizer(json: JSONObject) {
    private val model = json.getJSONObject("model")
    private val vocab = model.getJSONObject("vocab")
    private val ids = vocab.keys().asSequence().associateWith { vocab.getInt(it) }
    private val tokens = ids.entries.associate { it.value to it.key }
    private val ranks = mutableMapOf<Pair<String, String>, Int>()
    private val special = mutableSetOf<Int>()
    private val added = mutableMapOf<String, Int>()
    init {
        require(model.getString("type") == "BPE" && model.isNull("dropout"))
        require(json.getJSONObject("pre_tokenizer").getString("type") == "Metaspace")
        val merges = model.getJSONArray("merges")
        for (i in 0 until merges.length()) {
            val pair = merges.getJSONArray(i)
            ranks[pair.getString(0) to pair.getString(1)] = i
        }
        val extras = json.getJSONArray("added_tokens")
        for (i in 0 until extras.length()) {
            val token = extras.getJSONObject(i)
            added[token.getString("content")] = token.getInt("id")
            if (token.getBoolean("special")) special.add(token.getInt("id"))
        }
    }
    fun encode(text: String): List<Long> {
        val result = mutableListOf<Long>()
        val pattern = Regex(added.keys.sortedByDescending { it.length }.joinToString("|") { Regex.escape(it) })
        var start = 0
        for (match in pattern.findAll(text)) {
            if (match.range.first > start) result.addAll(encodeOrdinary(text.substring(start, match.range.first)))
            result.add(added.getValue(match.value).toLong())
            start = match.range.last + 1
        }
        if (start < text.length) result.addAll(encodeOrdinary(text.substring(start)))
        return result
    }
    private fun encodeOrdinary(text: String): List<Long> {
        var normalized = Normalizer.normalize(text, Normalizer.Form.NFKC).replace(" ", "▁")
        if (!normalized.startsWith("▁")) normalized = "▁" + normalized
        return normalized.split(Regex("(?=▁)")).filter { it.isNotEmpty() }.flatMap { word ->
            val pieces = word.codePoints().toArray().map {
                String(Character.toChars(it)).let { c -> if (ids.containsKey(c)) c else model.getString("unk_token") }
            }.toMutableList()
            while (pieces.size > 1) {
                var bestIndex = -1
                var bestRank = Int.MAX_VALUE
                for (i in 0 until pieces.size - 1) {
                    val rank = ranks[pieces[i] to pieces[i + 1]] ?: continue
                    if (rank < bestRank) { bestRank = rank; bestIndex = i }
                }
                if (bestIndex < 0) break
                pieces[bestIndex] += pieces[bestIndex + 1]
                pieces.removeAt(bestIndex + 1)
            }
            pieces.map { ids.getValue(it).toLong() }
        }
    }
    fun decode(ids: List<Long>): String = ids.filter { it.toInt() !in special }
        .map { tokens.getValue(it.toInt()) }.joinToString("").replace("▁", " ").trim()
}
