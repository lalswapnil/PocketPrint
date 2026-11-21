import SwiftUI

/// Renders template thumbnails once per launch.
@MainActor
final class TemplatePreviewCache {
    static let shared = TemplatePreviewCache()
    private let renderer = DesignRenderer()
    private var previews: [String: RasterPreview] = [:]

    func preview(for template: DesignTemplate) async -> RasterPreview? {
        if let cached = previews[template.id] { return cached }
        let rendered = await renderer.render(template.make(), purpose: .print)
        let preview = RasterPreview(rendered.bitmap)
        previews[template.id] = preview
        return preview
    }
}

struct TemplateCard: View {
    let template: DesignTemplate
    @State private var preview: RasterPreview?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                ZStack(alignment: .top) {
                    Color(.secondarySystemGroupedBackground)
                    if let preview {
                        Image(uiImage: preview.image)
                            .resizable()
                            .interpolation(.medium)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: proxy.size.width - 16)
                            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                            .padding(.top, 8)
                    } else {
                        ProgressView().padding(.top, 40)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                .clipped()
            }
            .aspectRatio(0.78, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Label(template.title, systemImage: template.systemImage)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .task { preview = await TemplatePreviewCache.shared.preview(for: template) }
    }
}

/// A short row of templates on the Create screen.
struct TemplateStrip: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Templates")
                    .font(.title3.bold())
                Spacer()
                Button("See All") { router.open(.templates) }
                    .font(.subheadline)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(Templates.all.prefix(8)) { template in
                        Button {
                            router.open(.design(DesignRoute(design: template.make())))
                        } label: {
                            TemplateCard(template: template)
                                .frame(width: 120)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

struct TemplateGalleryView: View {
    @Environment(AppRouter.self) private var router
    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ForEach(DesignTemplate.Category.allCases) { category in
                    let templates = Templates.all.filter { $0.category == category }
                    if !templates.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(category.rawValue)
                                .font(.title3.bold())
                            LazyVGrid(columns: columns, spacing: 18) {
                                ForEach(templates) { template in
                                    Button {
                                        router.open(.design(DesignRoute(design: template.make())))
                                    } label: {
                                        TemplateCard(template: template)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Templates")
    }
}
