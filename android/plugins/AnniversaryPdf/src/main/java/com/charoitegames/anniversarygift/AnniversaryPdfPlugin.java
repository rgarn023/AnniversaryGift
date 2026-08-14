package com.charoitegames.anniversarygift;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.net.Uri;
import android.util.Log;

import androidx.core.content.FileProvider;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

import java.io.File;

/**
 * Native Android helper for opening and sharing the bundled anniversary PDF
 * via content:// URIs (never raw file:// URIs).
 */
public class AnniversaryPdfPlugin extends GodotPlugin {
	private static final String TAG = "AnniversaryPdf";
	private static final String AUTHORITY_SUFFIX = ".fileprovider";

	public AnniversaryPdfPlugin(Godot godot) {
		super(godot);
	}

	@Override
	public String getPluginName() {
		return "AnniversaryPdf";
	}

	@UsedByGodot
	public String openPdf(String absolutePath) {
		Activity activity = getActivity();
		if (activity == null) {
			return "ERROR: Activity unavailable.";
		}
		try {
			Uri uri = buildContentUri(activity, absolutePath);
			if (uri == null) {
				return "ERROR: PDF file was not found.";
			}
			Intent viewIntent = new Intent(Intent.ACTION_VIEW);
			viewIntent.setDataAndType(uri, "application/pdf");
			viewIntent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
			viewIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
			Intent chooser = Intent.createChooser(viewIntent, "Open anniversary gift PDF");
			chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
			activity.startActivity(chooser);
			return "OK: Opened PDF chooser.";
		} catch (ActivityNotFoundException e) {
			Log.w(TAG, "No PDF viewer installed", e);
			return "ERROR: No PDF application is installed. Use the in-app page preview instead.";
		} catch (Exception e) {
			Log.e(TAG, "Failed to open PDF", e);
			return "ERROR: Unable to open PDF (" + e.getMessage() + ").";
		}
	}

	@UsedByGodot
	public String sharePdf(String absolutePath) {
		Activity activity = getActivity();
		if (activity == null) {
			return "ERROR: Activity unavailable.";
		}
		try {
			Uri uri = buildContentUri(activity, absolutePath);
			if (uri == null) {
				return "ERROR: PDF file was not found.";
			}
			Intent shareIntent = new Intent(Intent.ACTION_SEND);
			shareIntent.setType("application/pdf");
			shareIntent.putExtra(Intent.EXTRA_STREAM, uri);
			shareIntent.putExtra(Intent.EXTRA_SUBJECT, "Anniversary Gift");
			shareIntent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
			Intent chooser = Intent.createChooser(shareIntent, "Share or save anniversary gift PDF");
			chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
			activity.startActivity(chooser);
			return "OK: Opened share chooser.";
		} catch (ActivityNotFoundException e) {
			Log.w(TAG, "No share target for PDF", e);
			return "ERROR: No application is available to share or save the PDF.";
		} catch (Exception e) {
			Log.e(TAG, "Failed to share PDF", e);
			return "ERROR: Unable to share PDF (" + e.getMessage() + ").";
		}
	}

	private Uri buildContentUri(Activity activity, String absolutePath) {
		if (absolutePath == null || absolutePath.trim().isEmpty()) {
			return null;
		}
		File file = new File(absolutePath);
		if (!file.exists() || !file.isFile()) {
			Log.e(TAG, "Missing PDF at " + absolutePath);
			return null;
		}
		String authority = activity.getPackageName() + AUTHORITY_SUFFIX;
		return FileProvider.getUriForFile(activity, authority, file);
	}
}
