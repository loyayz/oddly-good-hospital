/* Strict hospital-backup policy over the pinned minizip-ng parser.
 * mz_zip has no public central-directory bounds accessor. Including the pinned
 * source here keeps that one version-dependent detail out of the Godot bridge;
 * all ZIP/ZIP64 headers, descriptors, compression and CRC use minizip/zlib.
 */
#include "mz.h"
#include "mz_strm.h"

/* A comment may itself contain PK\005\006. Preserve the restricted format's
 * exact EOF rule instead of accepting the library's last-signature heuristic. */
static int32_t ogh_zip_find_reverse(void *stream, const void *find, int32_t find_size,
                                   int64_t max_seek, int64_t *position) {
    int64_t end = mz_stream_tell(stream), lower = end - max_seek, candidate = 0, search_end = end;
    uint16_t comment = 0;
    const uint8_t *signature = (const uint8_t *)find;
    if (find_size != 4 || signature[0] != 0x50 || signature[1] != 0x4b || signature[2] != 5 || signature[3] != 6)
        return mz_stream_find_reverse(stream, find, find_size, max_seek, position);
    while (search_end - lower >= 4) {
        mz_stream_seek(stream, search_end, MZ_SEEK_SET);
        if (mz_stream_find_reverse(stream, find, find_size, search_end - lower, &candidate) != MZ_OK)
            break;
        if (candidate <= end - 22 && mz_stream_seek(stream, candidate + 20, MZ_SEEK_SET) == MZ_OK &&
            mz_stream_read_uint16(stream, &comment) == MZ_OK && candidate + 22 + comment == end) {
            *position = candidate;
            // mz_stream_find_reverse leaves the stream at the signature;
            // mz_zip_read_cd consumes it immediately without another seek.
            return mz_stream_seek(stream, candidate, MZ_SEEK_SET);
        }
        if (candidate <= lower)
            break;
        search_end = candidate;
    }
    return MZ_FORMAT_ERROR;
}

#define MZ_ZIP_EOCD_MAX_BACK 65557
#define mz_stream_find_reverse ogh_zip_find_reverse
#include "mz_zip.c"
#undef mz_stream_find_reverse

int64_t ogh_zip_directory_end(void *handle) {
    mz_zip *zip = (mz_zip *)handle;
    return zip->cd_offset + zip->cd_size;
}

int32_t ogh_zip_layout(void *handle, int64_t length, int64_t *directory) {
    mz_zip *zip = (mz_zip *)handle;
    int64_t end = 0, zip64_end = 0, record_size = 0;
    uint16_t disk = 0, count = 0, all_count = 0, comment = 0;
    uint32_t size32 = 0, offset32 = 0, signature = 0, disk32 = 0;
    uint64_t size64 = 0, count64 = 0;
    if (zip->disk_number_with_cd || zip->disk_offset_shift || zip->number_entry < 2 || zip->number_entry > 3 ||
        zip->cd_offset < 0 || zip->cd_size < 0 || zip->cd_size > length - zip->cd_offset)
        return MZ_FORMAT_ERROR;
    if (mz_zip_search_eocd(zip->stream, &end) != MZ_OK || end > length - 22 ||
        mz_stream_seek(zip->stream, end + 4, MZ_SEEK_SET) != MZ_OK ||
        mz_stream_read_uint16(zip->stream, &disk) != MZ_OK || disk ||
        mz_stream_read_uint16(zip->stream, &disk) != MZ_OK || disk ||
        mz_stream_read_uint16(zip->stream, &count) != MZ_OK ||
        mz_stream_read_uint16(zip->stream, &all_count) != MZ_OK || count != all_count ||
        mz_stream_read_uint32(zip->stream, &size32) != MZ_OK ||
        mz_stream_read_uint32(zip->stream, &offset32) != MZ_OK ||
        mz_stream_read_uint16(zip->stream, &comment) != MZ_OK || end + 22 + comment != length)
        return MZ_FORMAT_ERROR;
    if (all_count == UINT16_MAX || size32 == UINT32_MAX || offset32 == UINT32_MAX) {
        if (mz_zip_search_zip64_eocd(zip->stream, end, &zip64_end) != MZ_OK || zip64_end < 0 ||
            zip64_end > end - 76 || mz_stream_seek(zip->stream, zip64_end + 4, MZ_SEEK_SET) != MZ_OK ||
            mz_stream_read_int64(zip->stream, &record_size) != MZ_OK || record_size < 44 ||
            record_size != end - 32 - zip64_end ||
            mz_stream_seek(zip->stream, zip64_end + 16, MZ_SEEK_SET) != MZ_OK ||
            mz_stream_read_uint32(zip->stream, &disk32) != MZ_OK || disk32 ||
            mz_stream_read_uint32(zip->stream, &disk32) != MZ_OK || disk32 ||
            mz_stream_read_uint64(zip->stream, &count64) != MZ_OK || count64 != zip->number_entry ||
            mz_stream_read_uint64(zip->stream, &count64) != MZ_OK || count64 != zip->number_entry ||
            mz_stream_read_uint64(zip->stream, &size64) != MZ_OK || size64 != (uint64_t)zip->cd_size ||
            mz_stream_read_uint64(zip->stream, &size64) != MZ_OK || size64 != (uint64_t)zip->cd_offset ||
            mz_stream_seek(zip->stream, end - 20, MZ_SEEK_SET) != MZ_OK ||
            mz_stream_read_uint32(zip->stream, &signature) != MZ_OK || signature != MZ_ZIP_MAGIC_ENDLOCHEADER64 ||
            mz_stream_read_uint32(zip->stream, &disk32) != MZ_OK || disk32 ||
            mz_stream_read_int64(zip->stream, &record_size) != MZ_OK || record_size != zip64_end ||
            mz_stream_read_uint32(zip->stream, &disk32) != MZ_OK || disk32 != 1)
            return MZ_FORMAT_ERROR;
        end = zip64_end;
    } else if (all_count != zip->number_entry || size32 != zip->cd_size || offset32 != zip->cd_offset) {
        return MZ_FORMAT_ERROR;
    }
    if (zip->cd_size != end - zip->cd_offset)
        return MZ_FORMAT_ERROR;
    *directory = zip->cd_offset;
    return MZ_OK;
}

int32_t ogh_zip_descriptor(void *handle, int64_t position, uint8_t zip64, uint32_t *crc,
                          int64_t *compressed, int64_t *unpacked, int64_t *end) {
    mz_zip *zip = (mz_zip *)handle;
    int32_t result = mz_stream_seek(zip->stream, position, MZ_SEEK_SET);
    if (result == MZ_OK)
        result = mz_zip_entry_read_descriptor(zip->stream, zip64, crc, compressed, unpacked);
    *end = mz_stream_tell(zip->stream);
    return result;
}

/* Preserve the strict protocol's extra-field bounds and single ZIP64 field.
 * minizip normally tolerates truncated/duplicate extras for general archives.
 */
int32_t ogh_zip_extra(const mz_zip_file *info, int64_t raw_position, void *stream, uint8_t local) {
    void *extra = mz_stream_mem_create();
    uint16_t kind = 0, length = 0;
    uint32_t raw = 0;
    int64_t required = 0, cursor = 0;
    int32_t result = MZ_OK;
    uint8_t found = 0;
    int64_t saved = mz_stream_tell(stream);
    if (!extra)
        return MZ_MEM_ERROR;
    /* Only the three sentinel fields determine required ZIP64 values; their
     * decoding and the actual values remain owned by minizip-ng. */
    if (mz_stream_seek(stream, raw_position + (local ? 18 : 20), MZ_SEEK_SET) != MZ_OK ||
        mz_stream_read_uint32(stream, &raw) != MZ_OK)
        result = MZ_FORMAT_ERROR;
    if (raw == UINT32_MAX)
        required += 8;
    if (mz_stream_read_uint32(stream, &raw) != MZ_OK)
        result = MZ_FORMAT_ERROR;
    if (raw == UINT32_MAX)
        required += 8;
    if (!local) {
        uint16_t disk = 0;
        if (mz_stream_seek(stream, raw_position + 34, MZ_SEEK_SET) != MZ_OK ||
            mz_stream_read_uint16(stream, &disk) != MZ_OK || disk)
            result = MZ_FORMAT_ERROR;
        if (mz_stream_seek(stream, raw_position + 42, MZ_SEEK_SET) != MZ_OK ||
            mz_stream_read_uint32(stream, &raw) != MZ_OK)
            result = MZ_FORMAT_ERROR;
        if (raw == UINT32_MAX)
            required += 8;
    }
    mz_stream_mem_set_buffer(extra, (void *)info->extrafield, info->extrafield_size);
    while (result == MZ_OK && cursor < info->extrafield_size) {
        if (info->extrafield_size - cursor < 4 ||
            mz_zip_extrafield_read(extra, &kind, &length) != MZ_OK || length > info->extrafield_size - cursor - 4) {
            result = MZ_FORMAT_ERROR;
            break;
        }
        if (kind == MZ_ZIP_EXTENSION_ZIP64 && (found++ || length < required)) {
            result = MZ_FORMAT_ERROR;
            break;
        }
        cursor += 4 + length;
        mz_stream_seek(extra, cursor, MZ_SEEK_SET);
    }
    if (required && !found)
        result = MZ_FORMAT_ERROR;
    mz_stream_mem_delete(&extra);
    mz_stream_seek(stream, saved, MZ_SEEK_SET);
    return result;
}
