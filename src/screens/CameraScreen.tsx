import React, { useEffect } from 'react';
import {
  View,
  StyleSheet,
  DeviceEventEmitter,
} from 'react-native';
import { CameraView } from '../components/CameraView';
import { useNavigation } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import type { RootStackParamList } from '../../App';

type NavigationProp = NativeStackNavigationProp<RootStackParamList, 'Camera'>;

const CameraScreen: React.FC = () => {
  const navigation = useNavigation<NavigationProp>();

  useEffect(() => {
    const subscription = DeviceEventEmitter.addListener(
      'onImageCaptured',
      (event: { uri: string }) => {
        console.log('Image captured:', event.uri);
        navigation.navigate('Result', { imageUri: event.uri });
      }
    );

    return () => {
      subscription.remove();
    };
  }, [navigation]);

  return (
    <View style={styles.container}>
      <CameraView style={styles.camera} cameraType="front" />
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#000',
  },
  camera: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
  },
});

export default CameraScreen;
