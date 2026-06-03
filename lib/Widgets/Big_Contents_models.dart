class UnboardingContent {
  String image;
  String title;
  String description;

  UnboardingContent({
    required this.description,
    required this.image,
    required this.title,
  });
}

List<UnboardingContent> contents = [
  //1st screen//
  UnboardingContent(
    description:
        "Scan the QR code on the test kit. The app reads the kit name from the QR and prepares the submission form.",
    image: "assets/onboard1.png",
    title: "Scan Kit QR Code",
  ),
  //2nd screen//
  UnboardingContent(
    description:
        "Upload the test photo, then select only Positive or Negative. The result is saved with digital date and time.",
    image: "assets/onboard2.png",
    title: "Submit Test Result",
  ),
  //3rd screen//
  UnboardingContent(
    description:
        "Admin can review all records, filter by status/date, and download the dataset in CSV, Excel, or JSON format.",
    image: "assets/onboard3.png",
    title: "Manage Dataset",
  ),
];
