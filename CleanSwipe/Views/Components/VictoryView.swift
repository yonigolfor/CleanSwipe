import SwiftUI

struct VictoryView: View {
    let onEmptyBin: () -> Void
    
    var body: some View {
        VStack(spacing: 25) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.swipeGreen.opacity(0.2), .swipeGreen.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 140, height: 140)
                
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 70))
                    .foregroundColor(.swipeGreen)
                    .shadow(color: .swipeGreen.opacity(0.3), radius: 10, x: 0, y: 5)
            }
            .padding(.top, 40)
            
            VStack(spacing: 12) {
                Text("Gallery Cleaned! 🎉")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                
                Text("You've cleared your stack for now.\nCome back later for more!")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
             // CTA
            Button(action: onEmptyBin) {
                Text("Empty Review Bin")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Capsule().fill(Color.red.gradient))
            }
            .padding(.horizontal)
            
            Spacer()
        }
        .padding()
        .transition(.asymmetric(
            insertion: .scale.combined(with: .opacity),
            removal: .opacity
        ))
    }
}

#Preview {
    VictoryView(onEmptyBin: {})
}
