package com.badie.app.features.profile

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RectF
import android.media.ExifInterface
import androidx.core.graphics.createBitmap
import android.net.Uri
import android.os.Build
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.ClipOp
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import com.badie.app.design.AppTheme
import com.badie.app.design.TextAction
import com.badie.app.l10n.tr
import java.io.ByteArrayOutputStream
import java.io.IOException
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

// MARK: - 照片：选完先裁剪，再压成 JPEG 上传（对应 iPhone 的 Services/Haptics.swift 里的 AvatarPhotos 和 AvatarCropSheet.swift）

object AvatarPhotos {
    /** 头像：320×320 */
    val avatarSize = IntSize(320, 320)
    /** 卡片背景：竖图 600×800 */
    val cardSize = IntSize(600, 800)
    /** 服务器每张最多 256 KB，留点余量 */
    const val MAX_BYTES = 250_000

    /** 相册里选的照片：直接解码成长边不超过 1600 像素的图再裁（几千万像素的原图全尺寸解码要上百 MB），转正方向 */
    fun decode(context: Context, uri: Uri): Bitmap? = try {
        if (Build.VERSION.SDK_INT >= 28) {
            ImageDecoder.decodeBitmap(ImageDecoder.createSource(context.contentResolver, uri)) { decoder, info, _ ->
                val long = max(info.size.width, info.size.height)
                if (long > 1600) {
                    val k = 1600f / long
                    decoder.setTargetSize((info.size.width * k).roundToInt().coerceAtLeast(1), (info.size.height * k).roundToInt().coerceAtLeast(1))
                }
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            }
        } else {
            decodeLegacy(context, uri)
        }
    } catch (_: IOException) {
        null
    } catch (_: SecurityException) {
        null
    } catch (_: IllegalArgumentException) {
        null
    }

    /** Android 9 以前：先读尺寸算缩小倍数，再按 EXIF 转正（系统自带的 ExifInterface 从 Android 7 起就能读流，不另加依赖） */
    @android.annotation.SuppressLint("ExifInterface")
    private fun decodeLegacy(context: Context, uri: Uri): Bitmap? {
        val resolver = context.contentResolver
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= 1600) sample *= 2
        val bitmap = resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample }) }
            ?: return null
        val orientation = resolver.openInputStream(uri)?.use { ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL) }
            ?: ExifInterface.ORIENTATION_NORMAL
        val degrees = when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> 90f
            ExifInterface.ORIENTATION_ROTATE_180 -> 180f
            ExifInterface.ORIENTATION_ROTATE_270 -> 270f
            else -> return bitmap
        }
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, Matrix().apply { postRotate(degrees) }, true)
    }

    /** 按裁剪框（照片坐标）出 JPEG：默认 320×320 的头像。太大就再压一压；压到最低还超过就返回 null */
    fun jpegData(image: Bitmap, crop: RectF, size: IntSize = avatarSize): ByteArray? {
        if (crop.width() <= 0f || crop.height() <= 0f) return null
        val output = createBitmap(size.width, size.height)
        val canvas = android.graphics.Canvas(output)
        // JPEG 没有透明：透明的 PNG 先铺白底，不然是黑的
        canvas.drawColor(android.graphics.Color.WHITE)
        canvas.drawBitmap(image, android.graphics.Rect(crop.left.roundToInt(), crop.top.roundToInt(), crop.right.roundToInt(), crop.bottom.roundToInt()),
            android.graphics.Rect(0, 0, size.width, size.height), Paint(Paint.FILTER_BITMAP_FLAG))
        for (quality in listOf(80, 65, 50, 35)) {
            val bytes = ByteArrayOutputStream().also { output.compress(Bitmap.CompressFormat.JPEG, quality, it) }.toByteArray()
            if (bytes.size <= MAX_BYTES) return bytes
        }
        return null
    }

    /** 照片正好盖满整个框的倍数 */
    fun baseScale(frame: Size, imageWidth: Int, imageHeight: Int): Float =
        max(frame.width / max(1, imageWidth), frame.height / max(1, imageHeight))

    /** 照片始终盖住整个框，拖不出空白 */
    fun clamped(offset: Offset, frame: Size, imageWidth: Int, imageHeight: Int, zoom: Float): Offset {
        val scale = baseScale(frame, imageWidth, imageHeight) * zoom
        val maxX = max(0f, (imageWidth * scale - frame.width) / 2)
        val maxY = max(0f, (imageHeight * scale - frame.height) / 2)
        return Offset(offset.x.coerceIn(-maxX, maxX), offset.y.coerceIn(-maxY, maxY))
    }

    /** 框里看到的那一块，换成照片上的坐标 */
    fun cropRect(frame: Size, imageWidth: Int, imageHeight: Int, zoom: Float, offset: Offset): RectF {
        val scale = baseScale(frame, imageWidth, imageHeight) * zoom
        val width = frame.width / scale
        val height = frame.height / scale
        val centerX = imageWidth / 2f - offset.x / scale
        val centerY = imageHeight / 2f - offset.y / scale
        return RectF(centerX - width / 2, centerY - height / 2, centerX + width / 2, centerY + height / 2)
    }
}

/** 裁成什么：头像是圆框；卡片背景是 3:4 的竖框 */
enum class CropKind(val output: IntSize) {
    Avatar(AvatarPhotos.avatarSize), Card(AvatarPhotos.cardSize);

    /** 宽 / 高 */
    val aspect: Float get() = output.width.toFloat() / output.height
}

/** 选完照片：双指缩放（1–4 倍）、拖动。点“使用”出 JPEG */
@Composable
fun AvatarCropSheet(image: Bitmap, kind: CropKind, onDismiss: () -> Unit, onDone: (ByteArray) -> Unit) {
    var zoom by remember { mutableFloatStateOf(1f) }
    var offset by remember { mutableStateOf(Offset.Zero) }
    var frame by remember { mutableStateOf(Size(1f, 1f)) }
    val bitmap = remember(image) { image.asImageBitmap() }
    Column(Modifier.fillMaxWidth().padding(bottom = AppTheme.Spacing.xxl), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg), horizontalAlignment = Alignment.CenterHorizontally) {
        Row(Modifier.fillMaxWidth().padding(horizontal = AppTheme.Spacing.screen).padding(top = AppTheme.Spacing.lg), verticalAlignment = Alignment.CenterVertically) {
            TextAction(tr("取消"), onDismiss)
            Spacer(Modifier.weight(1f))
            Text(if (kind == CropKind.Avatar) tr("调整头像") else tr("调整卡片背景"), style = AppTheme.Typography.headline, color = AppTheme.colors.ink)
            Spacer(Modifier.weight(1f))
            TextAction(tr("使用"), {
                AvatarPhotos.jpegData(image, AvatarPhotos.cropRect(frame, image.width, image.height, zoom, offset), kind.output)?.let(onDone)
                onDismiss()
            }, color = AppTheme.colors.ink)
        }
        Box(
            Modifier
                .padding(horizontal = AppTheme.Spacing.screen)
                .fillMaxWidth(if (kind == CropKind.Avatar) 1f else 0.8f)
                .aspectRatio(kind.aspect)
                .onSizeChanged { frame = Size(it.width.toFloat(), it.height.toFloat()) }
                .pointerInput(image) {
                    detectTransformGestures { _, pan, gestureZoom, _ ->
                        zoom = min(4f, max(1f, zoom * gestureZoom))
                        offset = AvatarPhotos.clamped(offset + pan, frame, image.width, image.height, zoom)
                    }
                },
        ) {
            Canvas(Modifier.fillMaxSize()) {
                val scale = AvatarPhotos.baseScale(size, image.width, image.height) * zoom
                val w = image.width * scale
                val h = image.height * scale
                clipPath(Path().apply { addRect(androidx.compose.ui.geometry.Rect(Offset.Zero, size)) }) {
                    drawImage(
                        bitmap,
                        dstOffset = IntOffset((size.width / 2 - w / 2 + offset.x).roundToInt(), (size.height / 2 - h / 2 + offset.y).roundToInt()),
                        dstSize = IntSize(w.roundToInt(), h.roundToInt()),
                    )
                }
                if (kind == CropKind.Avatar) {
                    // 圆圈外面压暗
                    val circle = Path().apply { addOval(androidx.compose.ui.geometry.Rect(Offset.Zero, size)) }
                    clipPath(circle, ClipOp.Difference) { drawRect(Color.Black.copy(alpha = 0.45f)) }
                    drawCircle(Color.White, size.minDimension / 2 - 1.dp.toPx(), style = Stroke(2.dp.toPx()))
                } else {
                    drawRoundRect(
                        Color.White, Offset(1.dp.toPx(), 1.dp.toPx()), Size(size.width - 2.dp.toPx(), size.height - 2.dp.toPx()),
                        CornerRadius(AppTheme.Radius.lg.toPx()), style = Stroke(2.dp.toPx()),
                    )
                }
            }
        }
        Text(tr("双指缩放，拖动调整位置"), style = AppTheme.Typography.footnote, color = AppTheme.colors.inkSecondary)
    }
}
