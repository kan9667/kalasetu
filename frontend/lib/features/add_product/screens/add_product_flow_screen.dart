import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/providers/app_providers.dart';
import '../widgets/step_progress_bar.dart';
import '../widgets/step1_capture_widget.dart';
import '../widgets/step2_describe_widget.dart';
import '../widgets/step3_ai_review_widget.dart';
import '../widgets/step4_pricing_widget.dart';
import '../widgets/step5_confirm_widget.dart';

class AddProductFlowScreen extends ConsumerWidget {
  const AddProductFlowScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(addProductFlowProvider);
    final currentStep = draft.currentStep;

    final steps = const [
      Step1CaptureWidget(),
      Step2DescribeWidget(),
      Step3AiReviewWidget(),
      Step4PricingWidget(),
      Step5ConfirmWidget(),
    ];

    return AppScaffold(
      appBar: AppBar(
        title: Text('tab_add_product'.tr()),
        leading: currentStep > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  ref.read(addProductFlowProvider.notifier).previousStep();
                },
              )
            : null,
      ),
      body: Column(
        children: [
          StepProgressBar(
            currentStep: currentStep,
            onStepTapped: (step) {
              ref.read(addProductFlowProvider.notifier).setStep(step);
            },
          ),
          Expanded(
            child: IndexedStack(
              index: currentStep,
              children: steps,
            ),
          ),
        ],
      ),
    );
  }
}
