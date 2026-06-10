import SwiftUI

private let gold = Color(red: 1.0, green: 0.84, blue: 0.0)

struct StarRatingView: View {
    @Binding var rating: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .foregroundStyle(star <= rating ? gold : Color.white.opacity(0.3))
                    .font(.title3)
                    .onTapGesture {
                        rating = star == rating ? 0 : star
                    }
            }
        }
    }
}
