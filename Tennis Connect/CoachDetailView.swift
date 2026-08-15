//
//  CoachDetailView 2.swift
//  Tennis Connect
//
//  Created by 松崎徹郎 on 2026/08/15.
//


import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct CoachDetailView: View {

    let coach: Coach

    private let db = Firestore.firestore()

    @State private var isFavorite = false
    @State private var isUpdatingFavorite = false
    @State private var favoriteError = ""
    @State private var showFavoriteError = false

    var body: some View {

        ScrollView {

            VStack(spacing: 20) {

                CoachHeaderView(coach: coach)

                CoachProfileSection(coach: coach)

                CoachSkillSection()

                CoachVideoSection()

                CoachReviewSection(
                    coachId: coach.id
                )

                CoachScheduleSection(coach: coach)

                ReserveButton(coach: coach)

            }
            .padding()

        }
        .navigationTitle("コーチ詳細")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    toggleFavorite()
                } label: {
                    if isUpdatingFavorite {
                        ProgressView()
                    } else {
                        Image(
                            systemName: isFavorite
                                ? "heart.fill"
                                : "heart"
                        )
                        .foregroundStyle(
                            isFavorite ? .red : .primary
                        )
                    }
                }
                .disabled(isUpdatingFavorite)
                .accessibilityLabel(
                    isFavorite
                        ? "お気に入りから削除"
                        : "お気に入りに追加"
                )
            }
        }
        .onAppear {
            loadFavoriteState()
        }
        .alert(
            "お気に入りを更新できませんでした",
            isPresented: $showFavoriteError
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(favoriteError)
        }

    }

    private var favoriteDocumentId: String? {
        guard let studentId = Auth.auth().currentUser?.uid else {
            return nil
        }

        return "\(studentId)__\(coach.id)"
    }

    private func loadFavoriteState() {
        guard let documentId = favoriteDocumentId else {
            isFavorite = false
            return
        }

        db.collection("favorites")
            .document(documentId)
            .getDocument { snapshot, error in
                DispatchQueue.main.async {
                    if let error {
                        favoriteError = error.localizedDescription
                        showFavoriteError = true
                        return
                    }

                    isFavorite = snapshot?.exists == true
                }
            }
    }

    private func toggleFavorite() {
        guard let studentId = Auth.auth().currentUser?.uid,
              let documentId = favoriteDocumentId else {
            favoriteError =
                "お気に入り機能を使うにはログインが必要です"
            showFavoriteError = true
            return
        }

        isUpdatingFavorite = true

        let favoriteRef = db.collection("favorites")
            .document(documentId)

        if isFavorite {
            favoriteRef.delete { error in
                DispatchQueue.main.async {
                    isUpdatingFavorite = false

                    if let error {
                        favoriteError = error.localizedDescription
                        showFavoriteError = true
                        return
                    }

                    isFavorite = false
                }
            }
        } else {
            favoriteRef.setData(
                [
                    "studentId": studentId,
                    "coachId": coach.id,
                    "createdAt": Timestamp()
                ]
            ) { error in
                DispatchQueue.main.async {
                    isUpdatingFavorite = false

                    if let error {
                        favoriteError = error.localizedDescription
                        showFavoriteError = true
                        return
                    }

                    isFavorite = true
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        CoachDetailView(
            coach: sampleCoaches[0]
        )
    }
}
