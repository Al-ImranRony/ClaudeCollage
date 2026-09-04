//
//  CaroullageWidgetBundle.swift
//  CaroullageWidgets
//
//  The widgets this extension offers: the "Recent Collages" home screen widget
//  and the export Live Activity.
//

import WidgetKit
import SwiftUI

@available(iOS 17.0, *)
@main
struct CaroullageWidgetBundle: WidgetBundle {
    var body: some Widget {
        RecentProjectsWidget()
        // The in-progress export Live Activity (Step 04 slice 6b).
        ExportLiveActivity()
    }
}
