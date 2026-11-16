package com.badie.app.features.profile

import android.Manifest
import android.content.ClipData
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.badie.app.design.AppTheme
import com.badie.app.design.BrutalButton
import com.badie.app.design.ButtonKind
import com.badie.app.design.LoadingDots
import com.badie.app.design.Sym
import com.badie.app.design.Symbol
import com.badie.app.design.Toast
import com.badie.app.design.pressable
import com.badie.app.design.reduceMotion
import com.badie.app.design.rememberHaptics
import com.badie.app.l10n.L10n
import com.badie.app.l10n.tr
import com.badie.app.shell.LocalEnv
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException

/**
 * 等级卡片（看、翻面、分享、存到相册），半屏弹层的内容。“我的”、定级结果、球友资料都会调它，名字和参数不要改。
 * 对应 iPhone 的 Features/LevelCard/LevelCardViews.swift 里的 LevelCardSheet。
 * userId 为空 = 自己的卡片；iPhone 上只有自己的卡片，别人的 id 不显示
 */
@Composable
fun LevelCardSheet(userId: String? = null, onDismiss: () -> Unit) {
    val backend = LocalEnv.current.appState.backend
    val user = backend.currentUser ?: return
    if (userId != null && userId != user.id) return
    val api = rememberProfileApi()
    val data = remember(user) {
        LevelCardData.make(user, api.favoriteVenues().firstOrNull(), api.recurringSlots(), backend.photos.avatar(user.id))
    }
    LevelCardSheetContent(data, onDismiss)
}

/** 预览（点一下翻面）、印不印网址和头像、系统分享当前这一面（图片 + 链接）、存到相册 */
@Composable
fun LevelCardSheetContent(initial: LevelCardData, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val appState = LocalEnv.current.appState
    val haptics = rememberHaptics()
    val still = reduceMotion()
    var data by remember { mutableStateOf(initial) }
    var face by remember { mutableStateOf(LevelCardFace.Front) }
    // 两面都画好，翻面时不用等
    val images by produceState<Map<LevelCardFace, ImageBitmap>?>(null, data.showsURL, data.showsAvatar) {
        value = withContext(Dispatchers.Default) { LevelCardFace.entries.associateWith { LevelCardRenderer.render(context, data, it) } }
    }
    val angle by animateFloatAsState(if (face == LevelCardFace.Back) 180f else 0f, if (still) tween(0) else tween(450), label = "flip")
    fun flip() {
        haptics.selection()
        face = if (face == LevelCardFace.Front) LevelCardFace.Back else LevelCardFace.Front
    }
    val saveLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        val image = images?.get(face)
        if (granted && image != null) save(context, image, appState::showToast)
    }

    Column(Modifier.fillMaxWidth()) {
        SheetHeader(tr("等级卡片"), onDismiss, Modifier.padding(horizontal = AppTheme.Spacing.screen).padding(bottom = AppTheme.Spacing.md))
        Column(
            Modifier
                .weight(1f, fill = false)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = AppTheme.Spacing.screen)
                .padding(bottom = AppTheme.Spacing.lg),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.lg),
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Box(
                    Modifier
                        .fillMaxWidth()
                        .height(420.dp)
                        .clickable(remember { MutableInteractionSource() }, indication = null) { flip() }
                        .clearAndSetSemantics {
                            contentDescription = data.spokenSummary(face)
                            role = Role.Image
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    val shown = images
                    if (shown == null) {
                        LoadingDots()
                    } else {
                        // 绕竖轴转半圈，转到侧面时换成另一面
                        FaceImage(shown.getValue(LevelCardFace.Front), Modifier.graphicsLayer {
                            rotationY = angle
                            cameraDistance = 12 * density
                            alpha = if (angle < 90f) 1f else 0f
                        })
                        FaceImage(shown.getValue(LevelCardFace.Back), Modifier.graphicsLayer {
                            rotationY = angle - 180f
                            cameraDistance = 12 * density
                            alpha = if (angle >= 90f) 1f else 0f
                        })
                    }
                }
                Row(
                    Modifier.pressable { flip() }.padding(vertical = AppTheme.Spacing.sm, horizontal = AppTheme.Spacing.md),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Symbol(Sym.arrowLeftArrowRight, size = 13, tint = AppTheme.colors.inkSecondary)
                    androidx.compose.material3.Text(tr("翻面"), style = AppTheme.Typography.subheadlineBold, color = AppTheme.colors.inkSecondary)
                }
            }
            ToggleRow(tr("印上网址"), data.showsURL, { data = data.copy(showsURL = it) })
            if (data.avatar != null) ToggleRow(tr("印上头像"), data.showsAvatar, { data = data.copy(showsAvatar = it) })
        }
        val current = images?.get(face)
        Row(
            Modifier.padding(horizontal = AppTheme.Spacing.screen).padding(vertical = AppTheme.Spacing.md),
            horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm),
        ) {
            BrutalButton(
                {
                    val image = current ?: return@BrutalButton
                    // Android 10 以前存到相册要权限
                    if (Build.VERSION.SDK_INT < 29 &&
                        ContextCompat.checkSelfPermission(context, Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED
                    ) {
                        saveLauncher.launch(Manifest.permission.WRITE_EXTERNAL_STORAGE)
                    } else {
                        save(context, image, appState::showToast)
                    }
                },
                Modifier.weight(1f), kind = ButtonKind.Secondary, enabled = current != null,
            ) {
                Symbol(Sym.arrowDownCircleFill, size = 15)
                Spacer(Modifier.size(6.dp))
                androidx.compose.material3.Text(tr("保存"), maxLines = 1)
            }
            BrutalButton({ current?.let { share(context, it, data.link) } }, Modifier.weight(1.6f), enabled = current != null) {
                Symbol(Sym.squareAndArrowUp, size = 15)
                Spacer(Modifier.size(6.dp))
                androidx.compose.material3.Text(tr("分享"), maxLines = 1)
            }
        }
    }
}

@Composable
private fun FaceImage(image: ImageBitmap, modifier: Modifier) {
    Image(
        image, null,
        modifier
            .aspectRatio(LevelCardRenderer.WIDTH / LevelCardRenderer.HEIGHT)
            .clip(RoundedCornerShape(AppTheme.Radius.md)),
    )
}

/** 系统分享：图片 + “测测你几级：链接”。图片先存到缓存目录，用 FileProvider 给别的 App 读 */
private fun share(context: Context, image: ImageBitmap, link: String) {
    val file = try {
        val dir = File(context.cacheDir, "cards").apply { mkdirs() }
        File(dir, "Badie.png").also { file -> file.outputStream().use { image.asAndroidBitmap().compress(Bitmap.CompressFormat.PNG, 100, it) } }
    } catch (_: IOException) {
        return
    }
    val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
    val send = Intent(Intent.ACTION_SEND)
        .setType("image/png")
        .putExtra(Intent.EXTRA_STREAM, uri)
        .putExtra(Intent.EXTRA_TEXT, L10n.tr("测测你几级：%@", link))
        .putExtra(Intent.EXTRA_TITLE, L10n.tr("我的羽球卡"))
        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    send.clipData = ClipData.newRawUri(null, uri)
    context.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
}

/** 存到系统相册的“图片/Badie”里 */
private fun save(context: Context, image: ImageBitmap, toast: (String, Toast.Style) -> Unit) {
    val bitmap = image.asAndroidBitmap()
    val saved = try {
        if (Build.VERSION.SDK_INT >= 29) {
            val resolver = context.contentResolver
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, "Badie-${System.currentTimeMillis()}.png")
                put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                put(MediaStore.Images.Media.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/Badie")
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
            val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            uri != null && (resolver.openOutputStream(uri)?.use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) } ?: false).also {
                values.clear()
                values.put(MediaStore.Images.Media.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
            }
        } else {
            @Suppress("DEPRECATION")
            MediaStore.Images.Media.insertImage(context.contentResolver, bitmap, "Badie", null) != null
        }
    } catch (_: IOException) {
        false
    } catch (_: SecurityException) {
        false
    }
    if (saved) toast(L10n.tr("已保存"), Toast.Style.Success) else toast(L10n.tr("出了点问题，请重试。"), Toast.Style.Error)
}
