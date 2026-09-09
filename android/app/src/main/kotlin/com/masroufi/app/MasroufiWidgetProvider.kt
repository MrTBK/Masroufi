package com.masroufi.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Masroufi home-screen widget (brief §37): brand + total + today.
 *
 * Data is pushed from Dart (`MasroufiWidget.refreshFrom`) into the
 * plugin SharedPreferences; this provider only renders RemoteViews.
 * Tapping the body opens the app; tapping + opens the app via the
 * `masroufi://add?type=expense` deep link (cold start lands directly
 * in the expense form; warm start opens home — platform limitation).
 */
class MasroufiWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views =
                RemoteViews(context.packageName, R.layout.masroufi_widget).apply {
                    val openApp =
                        HomeWidgetLaunchIntent.getActivity(
                            context,
                            MainActivity::class.java,
                        )
                    setOnClickPendingIntent(R.id.widget_body, openApp)

                    // Path-style URI: go_router parses the path even from
                    // a full custom-scheme URI on cold start.
                    val addExpense =
                        HomeWidgetLaunchIntent.getActivity(
                            context,
                            MainActivity::class.java,
                            Uri.parse("masroufi:///add?type=expense"),
                        )
                    setOnClickPendingIntent(R.id.widget_add, addExpense)

                    setTextViewText(
                        R.id.widget_title,
                        widgetData.getString("title", null) ?: "Masroufi",
                    )
                    setTextViewText(
                        R.id.widget_balance,
                        widgetData.getString("balance", null) ?: "—",
                    )
                    setTextViewText(
                        R.id.widget_today,
                        widgetData.getString("today", null) ?: "",
                    )
                }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
