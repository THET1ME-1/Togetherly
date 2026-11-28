package com.togetherly.love.notif

import androidx.core.content.FileProvider
import com.togetherly.love.R

/**
 * Поставщик фото для переписки в шторке (`res/xml/notif_images.xml`). Свой
 * класс: два `androidx.core.content.FileProvider` в одном манифесте слияние
 * не пропустило бы, а плагины могут завести свой.
 */
class NotifImagesProvider : FileProvider(R.xml.notif_images)
