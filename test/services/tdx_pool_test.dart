import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';

void main() {
  group('TdxPool dynamic worker queue', () {
    test('faster worker should process more tasks', () async {
      final processedByWorker = <int, int>{0: 0, 1: 0};

      await TdxPool.runDynamicWorkerQueueForTesting(
        workerCount: 2,
        totalTasks: 12,
        runTask: (workerIndex, taskIndex) async {
          processedByWorker[workerIndex] =
              (processedByWorker[workerIndex] ?? 0) + 1;

          if (workerIndex == 0) {
            await Future<void>.delayed(const Duration(milliseconds: 1));
          } else {
            await Future<void>.delayed(const Duration(milliseconds: 8));
          }
        },
      );

      final fastWorkerTasks = processedByWorker[0] ?? 0;
      final slowWorkerTasks = processedByWorker[1] ?? 0;

      expect(fastWorkerTasks + slowWorkerTasks, 12);
      expect(
        fastWorkerTasks,
        greaterThan(slowWorkerTasks),
        reason: '动态调度下，快连接应自动承担更多股票任务，避免慢连接拖尾',
      );
    });

    test('covers every task exactly once', () async {
      final seenTaskIndexes = <int>{};

      await TdxPool.runDynamicWorkerQueueForTesting(
        workerCount: 3,
        totalTasks: 20,
        runTask: (workerIndex, taskIndex) async {
          expect(seenTaskIndexes.add(taskIndex), isTrue);
        },
      );

      expect(seenTaskIndexes.length, 20);
      expect(seenTaskIndexes.contains(0), isTrue);
      expect(seenTaskIndexes.contains(19), isTrue);
    });
  });
}
