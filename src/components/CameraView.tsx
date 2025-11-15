import React, { useEffect, useState } from 'react';
import {
  requireNativeComponent,
  ViewStyle,
  StyleSheet,
  View,
  Text,
  Button,
  Platform,
  PermissionsAndroid,
} from 'react-native';
import CameraXModule from '../modules/CameraXModule';

interface CameraViewProps {
  style?: ViewStyle;
  cameraType?: 'front' | 'back';
}

const NativeCameraView = requireNativeComponent<CameraViewProps>('CameraView');

export const CameraView: React.FC<CameraViewProps> = ({
  style,
  cameraType = 'back',
}) => {
  const [hasPermission, setHasPermission] = useState<boolean | null>(null);
  const [isChecking, setIsChecking] = useState<boolean>(true);
  const [error, setError] = useState<string>('');

  useEffect(() => {
    checkPermission();
  }, []);

  useEffect(() => {
    // Re-check permission when component mounts
    if (hasPermission === null) {
      checkPermission();
    }
  }, [hasPermission]);

  const checkPermission = async () => {
    try {
      if (Platform.OS !== 'android') {
        setError('CameraX is only available on Android');
        setIsChecking(false);
        return;
      }

      // Quick permission check first
      const granted = await CameraXModule.checkCameraPermission();
      
      if (granted) {
        // Permission already granted, start camera immediately
        setHasPermission(true);
        setIsChecking(false);
        return;
      }

      // Check if camera is available
      const hasCamera = await CameraXModule.isCameraAvailable();
      if (!hasCamera) {
        setError('No camera available on this device');
        setIsChecking(false);
        return;
      }
      
      setHasPermission(false);
      setError('Camera permission denied. Please grant permission in settings.');
      setIsChecking(false);
    } catch (error) {
      console.error('Error checking camera permission:', error);
      setError(`Error: ${error}`);
      setIsChecking(false);
    }
  };

  const requestPermission = async () => {
    try {
      const result = await PermissionsAndroid.request(
        PermissionsAndroid.PERMISSIONS.CAMERA,
        {
          title: 'Camera Permission',
          message: 'This app needs access to your camera for pose detection',
          buttonNeutral: 'Ask Me Later',
          buttonNegative: 'Cancel',
          buttonPositive: 'OK',
        }
      );
      
      if (result === PermissionsAndroid.RESULTS.GRANTED) {
        setHasPermission(true);
        setError('');
      } else {
        setError('Camera permission denied');
      }
    } catch (error) {
      console.error('Error requesting camera permission:', error);
      setError(`Error: ${error}`);
    }
  };

  if (isChecking) {
    return (
      <View style={[styles.container, style]}>
        <Text style={styles.text}>Checking camera permission...</Text>
      </View>
    );
  }

  if (error) {
    return (
      <View style={[styles.container, style]}>
        <Text style={styles.errorText}>{error}</Text>
        {!hasPermission && !error.includes('only available') && (
          <Button title="Grant Permission" onPress={requestPermission} />
        )}
      </View>
    );
  }

  if (!hasPermission) {
    return (
      <View style={[styles.container, style]}>
        <Text style={styles.text}>Camera permission is required</Text>
        <Button title="Grant Permission" onPress={requestPermission} />
      </View>
    );
  }

  console.log('Rendering NativeCameraView with cameraType:', cameraType);
  return <NativeCameraView style={style} cameraType={cameraType} />;
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: '#000',
  },
  text: {
    color: '#fff',
    marginBottom: 16,
    fontSize: 16,
  },
  errorText: {
    color: '#ff6b6b',
    marginBottom: 16,
    fontSize: 16,
    textAlign: 'center',
    paddingHorizontal: 20,
  },
});
