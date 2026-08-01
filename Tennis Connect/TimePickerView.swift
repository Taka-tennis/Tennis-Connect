//
//  TimePickerView.swift
//  Tennis Connect
//
//  Created by 松崎徹郎 on 2026/07/28.
//

import SwiftUI

struct TimePickerView: View {

    @Binding var selectedTime: Date

    var body: some View {
        DatePicker(
            "開始時間",
            selection: $selectedTime,
            displayedComponents: .hourAndMinute
        )
        .datePickerStyle(.wheel)
    }
}
