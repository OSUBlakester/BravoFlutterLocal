import 'package:flutter/material.dart';

class ComposeOptionsPage extends StatelessWidget {
  const ComposeOptionsPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Compose Options')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () {
                Navigator.pushNamed(
                  context,
                  '/freestyle',
                  arguments: {'composeMode': true, 'action': 'create'},
                );
              },
              child: const Text('Create New Composition'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pushNamed(
                  context,
                  '/freestyle',
                  arguments: {'composeMode': true, 'action': 'edit'},
                );
              },
              child: const Text('Edit Existing Composition'),
            ),
            ElevatedButton(
              onPressed: () {
                // Add logic for saving compositions
              },
              child: const Text('Save Composition'),
            ),
            ElevatedButton(
              onPressed: () {
                // Add logic for opening compositions
              },
              child: const Text('Open Composition'),
            ),
          ],
        ),
      ),
    );
  }
}
