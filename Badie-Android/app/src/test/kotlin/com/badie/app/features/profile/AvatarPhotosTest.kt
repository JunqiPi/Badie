package com.badie.app.features.profile

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import com.badie.app.models.SkillAssessment
import com.badie.app.models.SkillTier
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import kotlin.random.Random

/** 照片的裁剪和压缩、等级卡片的出图尺寸（要用 Android 的图片，跑在 Robolectric 上）。对应 iPhone 的 AvatarPhotoTests */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36])
class AvatarPhotosTest {
    /** 一张有噪点的照片（压起来不会太小） */
    private fun photo(width: Int, height: Int): Bitmap {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint()
        val random = Random(7)
        for (y in 0 until height step 4) for (x in 0 until width step 4) {
            paint.color = Color.rgb(random.nextInt(256), random.nextInt(256), random.nextInt(256))
            canvas.drawRect(x.toFloat(), y.toFloat(), x + 4f, y + 4f, paint)
        }
        return bitmap
    }

    @Test
    fun cropMath() {
        // 1600×1200 的横图放进 300×300 的圆框：按高铺满
        val frame = Size(300f, 300f)
        assertEquals(0.25f, AvatarPhotos.baseScale(frame, 1600, 1200), 0.0001f)
        // 不缩放：只能左右拖，拖不出空白
        assertEquals(Offset(50f, 0f), AvatarPhotos.clamped(Offset(400f, 80f), frame, 1600, 1200, 1f))
        val centered = AvatarPhotos.cropRect(frame, 1600, 1200, 1f, Offset.Zero)
        assertEquals(200f, centered.left, 0.01f)
        assertEquals(1200f, centered.width(), 0.01f)
        // 放大 2 倍、往右拖到头：看到的是左边那一块
        val zoomed = AvatarPhotos.cropRect(frame, 1600, 1200, 2f, AvatarPhotos.clamped(Offset(9999f, 0f), frame, 1600, 1200, 2f))
        assertEquals(0f, zoomed.left, 0.01f)
        assertEquals(600f, zoomed.width(), 0.01f)
    }

    @Test
    fun avatarAndCardJpegsFitTheServerLimit() {
        val image = photo(1600, 1200)
        val avatar = AvatarPhotos.jpegData(image, RectF(200f, 0f, 1400f, 1200f))
        assertNotNull(avatar)
        assertTrue(avatar!!.size <= 262_144)
        val decoded = BitmapFactory.decodeByteArray(avatar, 0, avatar.size)
        assertEquals(320, decoded.width)
        assertEquals(320, decoded.height)

        val card = AvatarPhotos.jpegData(image, RectF(500f, 0f, 1400f, 1200f), CropKind.Card.output)
        assertNotNull(card)
        assertTrue(card!!.size <= 262_144)
        val decodedCard = BitmapFactory.decodeByteArray(card, 0, card.size)
        assertEquals(600, decodedCard.width)
        assertEquals(800, decodedCard.height)

        assertNull("空的裁剪框", AvatarPhotos.jpegData(image, RectF(0f, 0f, 0f, 0f)))
    }

    @Test
    fun levelCardRendersAt1080By1350() {
        val result = SkillAssessment.evaluate(SkillAssessment.levelCardDemoAnswers)!!
        val data = LevelCardData(result.tier, LevelCardLabel.SelfRated, name = "阿杰#3400", play = result.play, gap = result.nextGap)
        for (face in LevelCardFace.entries) {
            val image = LevelCardRenderer.render(RuntimeEnvironment.getApplication(), data, face)
            assertEquals(1080, image.width)
            assertEquals(1350, image.height)
        }
        // 没有打法：只印等级
        val plain = LevelCardRenderer.render(RuntimeEnvironment.getApplication(), LevelCardData(SkillTier(7), LevelCardLabel.Verified), LevelCardFace.Front)
        assertEquals(1080, plain.width)
    }
}
