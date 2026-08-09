//
//  FontPreview.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 4/15/26.
//

import SwiftUI


struct FontPreview: View {
    let styles: [(String, Font)] = [
        ("Large Title", .largeTitle), ("Title", .title), ("Title 2", .title2),
        ("Title 3", .title3), ("Headline", .headline), ("Subheadline", .subheadline),
        ("Body", .body), ("Callout", .callout), ("Footnote", .footnote),
        ("Caption", .caption), ("Caption 2", .caption2)
    ]
    
    var body: some View {
        List(styles, id: \.0) { name, font in
            HStack {
                Text(name).font(font)
                Spacer()
                Text("Sample").font(font).foregroundColor(.secondary)
            }
        }
    }
}

#Preview(){
    FontPreview()
}
