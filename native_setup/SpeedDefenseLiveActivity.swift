import ActivityKit
import WidgetKit
import SwiftUI

struct SpeedDefenseLiveActivityAttributes: ActivityAttributes {
    public typealias ContentState = SpeedDefenseLiveActivityContentState

    public struct SpeedDefenseLiveActivityContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var speed: Int
        var limit: Int
        var isOverSpeed: Bool
    }
}

struct SpeedDefenseLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SpeedDefenseLiveActivityAttributes.self) { context in
            // Lock Screen/Banner UI
            HStack {
                // 左側：目前時速
                VStack(alignment: .leading) {
                    Text("\(context.state.speed)")
                        .font(.system(size: 48, weight: .heavy))
                        .foregroundColor(context.state.isOverSpeed ? .red : .green)
                    Text("km/h")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                // 右側：速限標誌
                ZStack {
                    Circle()
                        .stroke(Color.red, lineWidth: 4)
                        .background(Circle().fill(Color.white))
                        .frame(width: 50, height: 50)
                    
                    Text("\(context.state.limit)")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.black)
                }
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.8))
            .activitySystemActionForegroundColor(Color.white)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI (長按展開)
                DynamicIslandExpandedRegion(.leading) {
                    VStack {
                        Text("目前時速")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text("\(context.state.speed)")
                            .font(.system(size: 36, weight: .heavy))
                            .foregroundColor(context.state.isOverSpeed ? .red : .green)
                    }
                    .padding(.leading)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack {
                        Text("速限")
                            .font(.caption)
                            .foregroundColor(.gray)
                        ZStack {
                            Circle()
                                .stroke(Color.red, lineWidth: 3)
                                .background(Circle().fill(Color.white))
                                .frame(width: 40, height: 40)
                            Text("\(context.state.limit)")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.black)
                        }
                    }
                    .padding(.trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.isOverSpeed ? "⚠️ 嚴重超速" : "安全行駛中")
                        .font(.headline)
                        .foregroundColor(context.state.isOverSpeed ? .red : .green)
                        .padding(.top, 10)
                }
            } compactLeading: {
                // Compact Leading (未展開左側)
                Text("\(context.state.speed)")
                    .font(.headline)
                    .foregroundColor(context.state.isOverSpeed ? .red : .green)
            } compactTrailing: {
                // Compact Trailing (未展開右側)
                ZStack {
                    Circle().fill(Color.white)
                    Circle().stroke(Color.red, lineWidth: 2)
                    Text("\(context.state.limit)")
                        .font(.caption)
                        .foregroundColor(.black)
                        .bold()
                }
                .frame(width: 25, height: 25)
            } minimal: {
                // Minimal (當有多個動態島活動時)
                Text("\(context.state.speed)")
                    .foregroundColor(context.state.isOverSpeed ? .red : .green)
            }
        }
    }
}
